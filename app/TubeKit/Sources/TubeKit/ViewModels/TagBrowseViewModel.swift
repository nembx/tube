import Foundation
import Observation

/// 单个标签 / 热门分区的全量浏览 view model。
///
/// 给「查看全部」详情页用：支持分页加载，逻辑与旧版 HomeViewModel 单 tag 模式一致。
/// `tag == ""` 走 trending，否则走 `search(tag:)`。
@MainActor
@Observable
public final class TagBrowseViewModel {
    private static let trendingPageSize: Int = 24
    private static let taggedPageSize: Int = 20

    public let tag: String
    public let title: String

    public private(set) var items: [BangumiItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isLoadingMore: Bool = false
    public private(set) var hasMore: Bool = true
    public private(set) var loadFailed: Bool = false
    public private(set) var lastError: BangumiAPIError?

    private let api: BangumiAPIClientProtocol
    private var nextOffset: Int = 0
    private var loadGeneration: Int = 0

    public init(api: BangumiAPIClientProtocol, tag: String) {
        self.api = api
        self.tag = tag
        self.title = tag.isEmpty ? "热门番组" : tag
    }

    public func loadInitialIfNeeded() async {
        if !items.isEmpty || isLoading { return }
        await reload()
    }

    public func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        isLoadingMore = false
        loadFailed = false
        lastError = nil
        hasMore = true
        nextOffset = 0

        let result = await fetchPage(offset: 0)
        guard generation == loadGeneration else { return }

        switch result {
        case .success(let fetched):
            items = fetched
            nextOffset = fetched.count
            hasMore = fetched.count == pageSize
            loadFailed = false
            lastError = nil
        case .failure(let error):
            items = []
            hasMore = false
            loadFailed = true
            lastError = error
        }
        isLoading = false
    }

    public func loadMoreIfNeeded(currentItem item: BangumiItem) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard item.id == items.last?.id else { return }

        let generation = loadGeneration
        let offsetSnapshot = nextOffset
        isLoadingMore = true

        let result = await fetchPage(offset: offsetSnapshot)
        guard generation == loadGeneration else {
            isLoadingMore = false
            return
        }

        switch result {
        case .success(let fetched):
            items.append(contentsOf: fetched)
            nextOffset += fetched.count
            hasMore = fetched.count == pageSize
        case .failure(let error):
            lastError = error
        }
        isLoadingMore = false
    }

    public func cancel() {
        loadGeneration += 1
        isLoading = false
        isLoadingMore = false
    }

    private var pageSize: Int {
        tag.isEmpty ? Self.trendingPageSize : Self.taggedPageSize
    }

    private func fetchPage(offset: Int) async -> Result<[BangumiItem], BangumiAPIError> {
        do {
            let fetched: [BangumiItem]
            if tag.isEmpty {
                fetched = try await api.trending(limit: pageSize, offset: offset)
            } else {
                fetched = try await api.search(tag: tag, limit: pageSize, offset: offset)
            }
            return .success(fetched)
        } catch let error as BangumiAPIError {
            return .failure(error)
        } catch {
            return .failure(.transport(message: error.localizedDescription))
        }
    }
}
