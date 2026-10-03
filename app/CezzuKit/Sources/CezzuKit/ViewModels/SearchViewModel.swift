import Foundation
import Observation

/// Bangumi 搜索页的 view model。
@MainActor
@Observable
public final class SearchViewModel {
    public var text: String = ""
    /// 已选标签（多选，按加入顺序保留以保证 UI 稳定）。
    public var selectedTags: [String] = []
    public var selectedSort: BangumiSearchSort = .match
    /// 评分下限。`nil` 表示不限制。允许 0...10。
    public var ratingMin: Double? = nil
    /// 起始年份（含），`nil` 表示不限。
    public var yearMin: Int? = nil
    /// 结束年份（含），`nil` 表示不限。
    public var yearMax: Int? = nil
    /// 始终包含 R18 —— 产品决定不向用户暴露这个开关。
    private let includeNSFW: Bool = true

    public private(set) var isSearching: Bool = false
    public private(set) var results: [BangumiItem] = []
    public private(set) var lastError: BangumiAPIError?
    public private(set) var hasSearched: Bool = false
    public private(set) var hasMore: Bool = false
    public private(set) var isLoadingMore: Bool = false

    private static let pageSize: Int = 20
    /// 触发实时搜索的最小关键字长度（trim 后）。
    /// 1 个字符的查询既贵又噪声大，门槛设到 2。
    public static let liveSearchMinLength: Int = 2

    private let api: BangumiAPIClientProtocol
    /// 可变：iOS Root 会先注入 empty session 的 store，再在 persistent session 就绪后 `bindHistory` 切过去。
    private var history: SearchHistoryStoring?
    private let debounceMilliseconds: UInt64
    private var currentTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var nextOffset: Int = 0
    private var lastSubmittedKeyword: String = ""
    private var lastSubmittedSort: BangumiSearchSort = .match
    private var lastSubmittedFilter: BangumiSearchFilter = .default

    /// 兼容旧调用方：返回首个已选 tag。新代码请直接用 `selectedTags`。
    public var selectedTag: String? {
        get { selectedTags.first }
        set {
            if let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                selectedTags = [value]
            } else {
                selectedTags = []
            }
        }
    }

    /// 是否有任何高级筛选生效（用于 UI 上显示"已启用筛选"提示）。
    public var hasActiveAdvancedFilter: Bool {
        !selectedTags.isEmpty
            || ratingMin != nil
            || yearMin != nil
            || yearMax != nil
    }

    public init(
        api: BangumiAPIClientProtocol,
        history: SearchHistoryStoring? = nil,
        debounceMilliseconds: UInt64 = 350
    ) {
        self.api = api
        self.history = history
        self.debounceMilliseconds = debounceMilliseconds
    }

    /// 切换底层历史 store（不重置搜索态）。
    /// iOS 启动路径：empty → persistent 时由 Root 调用，避免历史写进会被丢弃的内存 store。
    public func bindHistory(_ history: SearchHistoryStoring?) {
        self.history = history
    }

    /// 历史关键字（最近在前），UI 直接绑定渲染。
    public var historyKeywords: [String] {
        history?.recent ?? []
    }

    public func submit() async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = makeFilter()
        guard !keyword.isEmpty || !filter.tags.isEmpty || filter != .default else { return }
        debounceTask?.cancel()
        currentTask?.cancel()
        results = []
        isSearching = true
        isLoadingMore = false
        lastError = nil
        hasSearched = true
        nextOffset = 0
        lastSubmittedKeyword = keyword
        lastSubmittedSort = selectedSort
        lastSubmittedFilter = filter

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await api.searchPage(
                    keyword: keyword,
                    sort: selectedSort,
                    filter: filter,
                    limit: Self.pageSize,
                    offset: 0
                )
                self.results = page.items
                self.nextOffset = page.nextOffset
                self.hasMore = page.hasMore
                self.lastError = nil
                if !keyword.isEmpty {
                    self.history?.record(keyword: keyword)
                }
            } catch let error as BangumiAPIError {
                self.results = []
                self.hasMore = false
                self.lastError = error
            } catch {
                self.results = []
                self.hasMore = false
                self.lastError = .transport(message: error.localizedDescription)
            }
            self.isSearching = false
        }
        await currentTask?.value
    }

    public func loadMoreIfNeeded(currentItem item: BangumiItem) async {
        guard hasMore, !isSearching, !isLoadingMore else { return }
        guard item.id == results.last?.id else { return }

        let keyword = lastSubmittedKeyword
        let filter = lastSubmittedFilter
        guard !keyword.isEmpty || !filter.tags.isEmpty || filter != .default else { return }
        let sort = lastSubmittedSort
        let offset = nextOffset
        isLoadingMore = true

        do {
            let page = try await api.searchPage(
                keyword: keyword,
                sort: sort,
                filter: filter,
                limit: Self.pageSize,
                offset: offset
            )
            results.append(contentsOf: page.items)
            nextOffset = page.nextOffset
            hasMore = page.hasMore
        } catch let error as BangumiAPIError {
            lastError = error
        } catch {
            lastError = .transport(message: error.localizedDescription)
        }

        isLoadingMore = false
    }

    public func cancel() {
        debounceTask?.cancel()
        currentTask?.cancel()
        isSearching = false
        isLoadingMore = false
    }

    /// 兼容旧调用方（DetailView 点 tag 跳搜索页）：把已选 tag 重置为这一个。
    public func applyTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedTags = [trimmed]
        text = ""
        debounceTask?.cancel()
    }

    /// 把一个 tag 加入多选列表。已存在时不变。
    public func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedTags.contains(trimmed) else { return }
        selectedTags.append(trimmed)
    }

    /// 从已选 tag 列表里移除一个；如已有搜索上下文则立即重搜。
    public func removeTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let beforeCount = selectedTags.count
        selectedTags.removeAll { $0 == trimmed }
        guard selectedTags.count != beforeCount else { return }
        advancedFilterChanged()
    }

    public func clearTag() {
        let hadTag = !selectedTags.isEmpty
        selectedTags = []
        if hadTag {
            advancedFilterChanged()
        }
    }

    /// 一键重置所有高级筛选项。
    public func resetAdvancedFilter() {
        let hadAny = hasActiveAdvancedFilter
        selectedTags = []
        ratingMin = nil
        yearMin = nil
        yearMax = nil
        if hadAny {
            advancedFilterChanged()
        }
    }

    /// 高级筛选项（tag / rating / year / nsfw）变化时由 View 调用。
    /// 已经有过一次有效搜索时立即重搜，否则按现有 keyword/tag 触发首次搜索（若条件足够）。
    public func advancedFilterChanged() {
        let hasContext = !lastSubmittedKeyword.isEmpty
            || !lastSubmittedFilter.tags.isEmpty
            || lastSubmittedFilter != .default
        let canSubmitNow = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasActiveAdvancedFilter
        guard hasContext || canSubmitNow else { return }
        scheduleImmediateSubmit()
    }

    /// 完全清空搜索框并取消任何挂起的请求。给 UI 上的清空按钮。
    public func clearText() {
        text = ""
        debounceTask?.cancel()
    }

    /// 用户从历史记录里点了一条 —— 写回输入框并立即搜索（绕过 debounce）。
    public func applyHistory(_ keyword: String) async {
        text = keyword
        debounceTask?.cancel()
        await submit()
    }

    /// 删除一条历史记录。
    public func deleteHistory(_ keyword: String) {
        history?.delete(keyword: keyword)
    }

    /// 清空全部历史。
    public func clearHistory() {
        history?.clearAll()
    }

    /// 输入框文本变化时由 View 调用。会以 `debounceMilliseconds` 防抖后自动 submit。
    /// trim 后短于 `liveSearchMinLength` 的 keyword 不触发实时搜索（同时取消挂起请求）。
    public func textChanged() {
        debounceTask?.cancel()
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.count < Self.liveSearchMinLength && !hasActiveAdvancedFilter {
            // 关键字过短且没有任何 advanced filter 兜底：取消挂起，不触发请求。
            return
        }
        let delay = debounceMilliseconds
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.submit()
        }
    }

    /// 排序变化时由 View 调用。如果已经有已生效的搜索上下文，立即重搜；否则什么都不做。
    public func sortChanged() {
        let hasContext = !lastSubmittedKeyword.isEmpty
            || !lastSubmittedFilter.tags.isEmpty
            || lastSubmittedFilter != .default
        guard hasContext else { return }
        scheduleImmediateSubmit()
    }

    /// 把一次"立即 submit"包到 `debounceTask` 上，保证 `waitForIdle()` 能等到它完成。
    /// 调用方负责确认上下文（keyword 或 tag）非空。
    private func scheduleImmediateSubmit() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            await self?.submit()
        }
    }

    /// 仅供测试 / UI 等候动画用，等待挂起的 debounce + 当前请求完成。
    public func waitForIdle() async {
        await debounceTask?.value
        await currentTask?.value
    }

    /// 把 ViewModel 的 advanced state 拼成 `BangumiSearchFilter`。
    private func makeFilter() -> BangumiSearchFilter {
        var filter = BangumiSearchFilter(
            tags: selectedTags,
            ratingMin: ratingMin,
            includeNSFW: includeNSFW
        )
        filter.setYearRange(min: yearMin, max: yearMax)
        return filter
    }
}
