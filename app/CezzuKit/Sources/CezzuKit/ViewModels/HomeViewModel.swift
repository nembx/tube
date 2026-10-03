import Foundation
import Observation

/// 首页一个分区的标识（热门 / 某个 tag）。
public struct HomeSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// 空字符串表示热门（trending）；非空则走 tag 搜索。
    public let tag: String

    public init(id: String, title: String, tag: String) {
        self.id = id
        self.title = title
        self.tag = tag
    }

    public static let trending = HomeSection(id: "trending", title: "热门番组", tag: "")
}

/// 首页分区的运行时状态（items + loading）。
public struct HomeSectionContent: Identifiable, Sendable {
    public var id: String { section.id }
    public let section: HomeSection
    public var items: [BangumiItem]
    public var isLoading: Bool
    public var loadFailed: Bool
    public var lastError: BangumiAPIError?
    /// 是否已完成至少一次请求（成功空列表也算），避免 LazyVStack 反复触发加载。
    public var hasLoaded: Bool

    public init(
        section: HomeSection,
        items: [BangumiItem] = [],
        isLoading: Bool = false,
        loadFailed: Bool = false,
        lastError: BangumiAPIError? = nil,
        hasLoaded: Bool = false
    ) {
        self.section = section
        self.items = items
        self.isLoading = isLoading
        self.loadFailed = loadFailed
        self.lastError = lastError
        self.hasLoaded = hasLoaded
    }
}

/// 主页 view model —— 按分区横向展示「热门 + 各 tag」，每区默认预览 N 条。
///
/// 顶部沉浸式 Banner 取自热门前 5 的磁盘缓存，仅 id 序列变化时刷新。
/// 不再维护单一 currentTag / 下拉切换；「查看全部」由 `TagBrowseViewModel` 接管。
@MainActor
@Observable
public final class HomeViewModel {
    /// 每个分区首页预览条数。
    public static let previewPageSize: Int = 20

    /// Kazumi 默认的 15 个 anime tag，hardcoded（这是 Kazumi 上游的设计）。
    public static let availableTags: [String] = [
        "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱",
        "悬疑", "热血", "后宫", "机战", "轻改", "偶像", "治愈", "异世界",
    ]

    /// 首页固定分区顺序：热门 + 全部 tag。
    public static var homeSections: [HomeSection] {
        [HomeSection.trending] + availableTags.map { tag in
            HomeSection(id: tag, title: tag, tag: tag)
        }
    }

    public private(set) var sections: [HomeSectionContent] = []
    /// 是否至少有一个分区已成功拉过数据（用于 loadInitialIfNeeded 短路）。
    public private(set) var hasLoadedAny: Bool = false

    /// 沉浸式 Banner 条目（热门前 5，来自缓存 / 同步）。
    public private(set) var bannerItems: [BangumiItem] = []
    /// 当前 Banner 页 index（驱动全页渐变）。
    public var activeBannerIndex: Int = 0
    /// subject id → 封面色板。
    public private(set) var bannerPalettes: [Int: CoverColorPalette] = [:]

    /// 当前页对应色板（无数据时用 fallback）。
    public var activeBannerPalette: CoverColorPalette {
        guard bannerItems.indices.contains(activeBannerIndex) else {
            return .fallback
        }
        let id = bannerItems[activeBannerIndex].id
        return bannerPalettes[id] ?? .fallback
    }

    private let api: BangumiAPIClientProtocol
    private let bannerStore: HomeBannerStore
    private let paletteStore: BannerPaletteStore
    /// 每个分区的加载世代；取消 / 重入时丢弃过期结果，避免写回错误状态。
    private var sectionGeneration: [String: Int] = [:]
    /// 正在取色的 subject，避免重复下载。
    private var paletteTasks: Set<Int> = []

    public init(
        api: BangumiAPIClientProtocol,
        bannerStore: HomeBannerStore = HomeBannerStore(),
        paletteStore: BannerPaletteStore = BannerPaletteStore()
    ) {
        self.api = api
        self.bannerStore = bannerStore
        self.paletteStore = paletteStore
        // 首帧即可用：骨架 + Banner 磁盘缓存 + 上次算好的色板，避免空黑屏等 .task
        bannerPalettes = paletteStore.load()
        ensureSectionsReady()
    }

    /// 保证 `sections` 骨架已就位，并灌入 Banner 磁盘缓存（不发网络请求）。
    public func ensureSectionsReady() {
        if sections.isEmpty {
            sections = Self.homeSections.map { HomeSectionContent(section: $0) }
        }
        if bannerItems.isEmpty {
            let cached = bannerStore.load()
            if !cached.isEmpty {
                bannerItems = cached
                clampActiveBannerIndex()
            }
        }
    }

    /// 启动时调用 —— 骨架 + **优先拉热门**（Banner / 热门区秒出），其它 tag 仍由视口 `.task` 懒加载。
    public func loadInitialIfNeeded() async {
        ensureSectionsReady()
        await loadSectionIfNeeded(HomeSection.trending.id)
        // 当前页色板优先；其余后台预取，不挡首屏
        if let first = bannerItems.first {
            await loadPaletteIfNeeded(for: first)
        }
        Task { await prefetchRemainingBannerPalettes() }
    }

    /// 强制重拉所有分区（下拉刷新）。串行加载，避免启动 / 刷新时 16 路并发打爆主线程 Observation。
    public func reload() async {
        sectionGeneration = [:]
        hasLoadedAny = false
        sections = Self.homeSections.map { HomeSectionContent(section: $0) }

        for section in Self.homeSections {
            await loadSectionIfNeeded(section.id, force: true)
        }
    }

    /// 分区出现在视口时调用。已加载 / 加载中则跳过（除非 force）。
    public func loadSectionIfNeeded(_ sectionID: String, force: Bool = false) async {
        ensureSectionsReady()
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let content = sections[index]
        if !force {
            if content.isLoading || content.hasLoaded { return }
        }

        let generation = (sectionGeneration[sectionID] ?? 0) + 1
        sectionGeneration[sectionID] = generation

        var loading = content
        loading.isLoading = true
        loading.loadFailed = false
        loading.lastError = nil
        if force {
            loading.items = []
            loading.hasLoaded = false
        }
        sections[index] = loading

        let section = content.section
        let limit = Self.previewPageSize
        let result: Result<[BangumiItem], BangumiAPIError>
        do {
            let fetched: [BangumiItem]
            if section.tag.isEmpty {
                fetched = try await api.trending(limit: limit, offset: 0)
            } else {
                fetched = try await api.search(tag: section.tag, limit: limit, offset: 0)
            }
            result = .success(fetched)
        } catch let error as BangumiAPIError {
            result = .failure(error)
        } catch {
            result = .failure(.transport(message: error.localizedDescription))
        }

        // 过期世代或任务已取消：不要把半截状态写回去卡住 isLoading。
        guard sectionGeneration[sectionID] == generation else { return }
        if Task.isCancelled {
            if let idx = sections.firstIndex(where: { $0.id == sectionID }) {
                var cleared = sections[idx]
                cleared.isLoading = false
                sections[idx] = cleared
            }
            return
        }

        guard let idx = sections.firstIndex(where: { $0.id == sectionID }) else { return }
        var updated = sections[idx]
        updated.isLoading = false
        updated.hasLoaded = true
        switch result {
        case .success(let items):
            updated.items = items
            updated.loadFailed = false
            updated.lastError = nil
            if !items.isEmpty {
                hasLoadedAny = true
            }
            if section.tag.isEmpty {
                syncBanner(from: items)
            }
        case .failure(let error):
            updated.items = []
            updated.loadFailed = true
            updated.lastError = error
        }
        sections[idx] = updated
    }

    /// 分区失败后手动重试。
    public func retrySection(_ sectionID: String) async {
        await loadSectionIfNeeded(sectionID, force: true)
    }

    public func cancel() {
        // 抬高所有世代，使进行中的请求结果被丢弃。
        for key in sectionGeneration.keys {
            sectionGeneration[key, default: 0] += 1
        }
        for index in sections.indices {
            var content = sections[index]
            content.isLoading = false
            sections[index] = content
        }
    }

    /// Banner 轮播切页。
    public func setActiveBannerIndex(_ index: Int) {
        guard !bannerItems.isEmpty else {
            activeBannerIndex = 0
            return
        }
        activeBannerIndex = min(max(0, index), bannerItems.count - 1)
        let item = bannerItems[activeBannerIndex]
        Task { await loadPaletteIfNeeded(for: item) }
    }

    /// 为 Banner 条目取封面色（已有则跳过）。
    /// 网络 / 解码在后台跑；写入 `bannerPalettes` 回主线程。
    public func loadPaletteIfNeeded(for item: BangumiItem) async {
        if bannerPalettes[item.id] != nil { return }
        guard !paletteTasks.contains(item.id) else { return }
        paletteTasks.insert(item.id)
        defer { paletteTasks.remove(item.id) }

        // 取色用小图：grid/small/medium，避免下 large 原图
        guard let urlString = paletteURLString(for: item),
              let url = URL(string: urlString)
        else {
            bannerPalettes[item.id] = .fallback
            return
        }

        let palette = await CoverColorExtractor.loadAndExtract(from: url) ?? .fallback
        bannerPalettes[item.id] = palette
        paletteStore.store(palette, for: item.id)
    }

    /// 预热全部 Banner 色板（首张优先已在 `loadInitialIfNeeded` 完成时调用其余）。
    public func prefetchBannerPalettes() async {
        if let first = bannerItems.first {
            await loadPaletteIfNeeded(for: first)
        }
        await prefetchRemainingBannerPalettes()
    }

    // MARK: - private

    /// 其余页色板：并发后台，不阻塞首屏。
    private func prefetchRemainingBannerPalettes() async {
        let rest = Array(bannerItems.dropFirst().prefix(HomeBannerStore.maxCount))
        guard !rest.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for item in rest {
                group.addTask { await self.loadPaletteIfNeeded(for: item) }
            }
        }
    }

    private func paletteURLString(for item: BangumiItem) -> String? {
        // 小 → 大：色板不需要高清
        let candidates = [
            item.images.grid,
            item.images.small,
            item.images.medium,
            item.images.common,
            item.images.listBest,
            item.images.best,
        ]
        for raw in candidates {
            if let s = nonEmptyURL(raw) { return s }
        }
        return nil
    }

    private func syncBanner(from trending: [BangumiItem]) {
        let didUpdate = bannerStore.updateIfNeeded(from: trending)
        let next = bannerStore.load()
        if didUpdate || bannerItems.isEmpty {
            bannerItems = next
            clampActiveBannerIndex()
            if let first = bannerItems.first {
                Task { await loadPaletteIfNeeded(for: first) }
            }
            Task { await prefetchRemainingBannerPalettes() }
        }
    }

    private func clampActiveBannerIndex() {
        if bannerItems.isEmpty {
            activeBannerIndex = 0
        } else {
            activeBannerIndex = min(activeBannerIndex, bannerItems.count - 1)
        }
    }

    private func nonEmptyURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
