import Foundation
import Testing
@testable import TubeKit

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {

    /// 一个内存版 Bangumi client，给 view model 单测用。
    /// 计数器用锁保护：`HomeViewModel.reload` 会并发打多个分区。
    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        var trendingResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        var searchResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        var keywordSearchResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        /// 按 tag 覆盖 search 返回；未命中时回落到 `searchResult`。
        var searchResultsByTag: [String: Result<[BangumiItem], BangumiAPIError>] = [:]
        private(set) var trendingCalls: Int = 0
        private(set) var trendingLimits: [Int] = []
        private(set) var searchCalls: [String] = []
        private(set) var searchOffsets: [Int] = []
        private(set) var searchLimits: [Int] = []
        private(set) var keywordSearchCalls: [(String, BangumiSearchSort, Int)] = []
        private(set) var keywordSearchFilters: [BangumiSearchFilter] = []

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] {
            switch recordTrending(limit: limit) {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] {
            switch recordSearch(tag: tag, limit: limit, offset: offset) {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        func search(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] {
            switch recordKeywordSearch(keyword: keyword, sort: sort, filter: filter, offset: offset) {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        private func recordTrending(limit: Int) -> Result<[BangumiItem], BangumiAPIError> {
            lock.lock()
            defer { lock.unlock() }
            trendingCalls += 1
            trendingLimits.append(limit)
            return trendingResult
        }

        private func recordSearch(
            tag: String,
            limit: Int,
            offset: Int
        ) -> Result<[BangumiItem], BangumiAPIError> {
            lock.lock()
            defer { lock.unlock() }
            searchCalls.append(tag)
            searchOffsets.append(offset)
            searchLimits.append(limit)
            return searchResultsByTag[tag] ?? searchResult
        }

        private func recordKeywordSearch(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            offset: Int
        ) -> Result<[BangumiItem], BangumiAPIError> {
            lock.lock()
            defer { lock.unlock() }
            keywordSearchCalls.append((keyword, sort, offset))
            keywordSearchFilters.append(filter)
            return keywordSearchResult
        }

        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            BangumiItem(
                id: subjectID, name: "", nameCn: "", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            )
        }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { [] }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { [] }
    }

    static func makeItem(id: Int, name: String) -> BangumiItem {
        BangumiItem(
            id: id, name: name, nameCn: name,
            summary: "", airDate: "", rank: 0, ratingScore: 0,
            images: .empty, tags: []
        )
    }

    @Test("homeSections is trending plus all available tags")
    func homeSectionsComposition() {
        let sections = HomeViewModel.homeSections
        #expect(sections.count == 1 + HomeViewModel.availableTags.count)
        #expect(sections.first == HomeSection.trending)
        #expect(sections.first?.tag == "")
        #expect(sections[1].title == "日常")
        #expect(sections[1].tag == "日常")
        #expect(sections.last?.tag == "异世界")
    }

    @Test("availableTags is the Kazumi-compat 15-tag list")
    func availableTagsContent() {
        #expect(HomeViewModel.availableTags.count == 15)
        #expect(HomeViewModel.availableTags.first == "日常")
        #expect(HomeViewModel.availableTags.contains("治愈"))
        #expect(HomeViewModel.availableTags.contains("异世界"))
    }

    @Test("init builds section skeleton and hydrates banner cache without network")
    func initBuildsSkeletonWithoutNetwork() {
        let api = FakeBangumiAPI()
        let vm = HomeViewModel(api: api)

        #expect(vm.sections.count == HomeViewModel.homeSections.count)
        #expect(vm.sections.allSatisfy { $0.items.isEmpty && !$0.hasLoaded && !$0.isLoading })
        #expect(api.trendingCalls == 0)
        #expect(api.searchCalls.isEmpty)
    }

    @Test("loadInitialIfNeeded prioritizes trending fetch")
    func loadInitialFetchesTrending() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A"), Self.makeItem(id: 2, name: "B")])
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()

        #expect(api.trendingCalls == 1)
        #expect(api.searchCalls.isEmpty)
        let trending = vm.sections.first { $0.id == HomeSection.trending.id }
        #expect(trending?.items.map(\.id) == [1, 2])
        #expect(vm.bannerItems.map(\.id) == [1, 2])
    }

    @Test("loadSectionIfNeeded fetches trending for empty tag")
    func loadTrendingSection() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A"), Self.makeItem(id: 2, name: "B")])
        let vm = HomeViewModel(api: api)
        await vm.loadInitialIfNeeded()

        await vm.loadSectionIfNeeded(HomeSection.trending.id)

        let section = vm.sections.first { $0.id == HomeSection.trending.id }
        #expect(api.trendingCalls == 1)
        #expect(api.trendingLimits == [HomeViewModel.previewPageSize])
        #expect(section?.items.count == 2)
        #expect(section?.hasLoaded == true)
        #expect(section?.isLoading == false)
        #expect(section?.loadFailed == false)
        #expect(vm.hasLoadedAny == true)
    }

    @Test("loadSectionIfNeeded fetches tag search with preview page size")
    func loadTaggedSection() async {
        let api = FakeBangumiAPI()
        api.searchResult = .success([
            Self.makeItem(id: 10, name: "K1"),
            Self.makeItem(id: 11, name: "K2"),
        ])
        let vm = HomeViewModel(api: api)
        await vm.loadInitialIfNeeded()

        await vm.loadSectionIfNeeded("治愈")

        #expect(api.searchCalls == ["治愈"])
        #expect(api.searchLimits == [HomeViewModel.previewPageSize])
        #expect(api.searchOffsets == [0])
        let section = vm.sections.first { $0.id == "治愈" }
        #expect(section?.items.map(\.id) == [10, 11])
        #expect(section?.hasLoaded == true)
    }

    @Test("loadSectionIfNeeded is a no-op when already loaded")
    func loadSectionSkipsWhenLoaded() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A")])
        let vm = HomeViewModel(api: api)

        await vm.loadSectionIfNeeded(HomeSection.trending.id)
        await vm.loadSectionIfNeeded(HomeSection.trending.id)

        #expect(api.trendingCalls == 1)
    }

    @Test("section failure sets loadFailed without poisoning other sections")
    func sectionFailureIsolated() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .failure(.http(status: 500))
        api.searchResultsByTag["日常"] = .success([Self.makeItem(id: 9, name: "D")])
        let vm = HomeViewModel(api: api)

        await vm.loadSectionIfNeeded(HomeSection.trending.id)
        await vm.loadSectionIfNeeded("日常")

        let trending = vm.sections.first { $0.id == HomeSection.trending.id }
        let daily = vm.sections.first { $0.id == "日常" }
        #expect(trending?.loadFailed == true)
        #expect(trending?.items.isEmpty == true)
        #expect(trending?.hasLoaded == true)
        #expect(daily?.items.map(\.id) == [9])
        #expect(daily?.loadFailed == false)
    }

    @Test("retrySection force-reloads a failed section")
    func retrySectionReloads() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .failure(.http(status: 500))
        let vm = HomeViewModel(api: api)

        await vm.loadSectionIfNeeded(HomeSection.trending.id)
        #expect(vm.sections.first?.loadFailed == true)

        api.trendingResult = .success([Self.makeItem(id: 3, name: "OK")])
        await vm.retrySection(HomeSection.trending.id)

        #expect(api.trendingCalls == 2)
        #expect(vm.sections.first?.items.map(\.id) == [3])
        #expect(vm.sections.first?.loadFailed == false)
    }

    @Test("reload rebuilds all sections and fetches them")
    func reloadFetchesAll() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "T")])
        api.searchResult = .success([Self.makeItem(id: 2, name: "S")])
        let vm = HomeViewModel(api: api)

        await vm.reload()

        #expect(api.trendingCalls == 1)
        #expect(api.searchCalls.count == HomeViewModel.availableTags.count)
        #expect(vm.sections.allSatisfy { $0.hasLoaded })
        #expect(vm.sections.first?.items.map(\.id) == [1])
        #expect(vm.hasLoadedAny == true)
    }

    @Test("previewPageSize is 20")
    func previewPageSizeIs20() {
        #expect(HomeViewModel.previewPageSize == 20)
    }

    @Test("init hydrates banner from disk cache without network")
    func initHydratesBannerCache() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-vm-banner-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HomeBannerStore(fileURL: url)
        let cached = (1...5).map { Self.makeItem(id: $0, name: "C\($0)") }
        #expect(store.updateIfNeeded(from: cached) == true)

        let api = FakeBangumiAPI()
        let vm = HomeViewModel(api: api, bannerStore: store)

        #expect(vm.bannerItems.map(\.id) == [1, 2, 3, 4, 5])
        #expect(api.trendingCalls == 0)
    }

    @Test("trending success updates banner when top five ids change")
    func trendingUpdatesBannerOnIDChange() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-vm-banner-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HomeBannerStore(fileURL: url)
        #expect(store.updateIfNeeded(from: (1...5).map { Self.makeItem(id: $0, name: "O\($0)") }) == true)

        let api = FakeBangumiAPI()
        api.trendingResult = .success((10...20).map { Self.makeItem(id: $0, name: "T\($0)") })
        let vm = HomeViewModel(api: api, bannerStore: store)
        // init 先用缓存
        #expect(vm.bannerItems.map(\.id) == [1, 2, 3, 4, 5])

        // loadInitial 优先拉热门，id 变了就换 Banner
        await vm.loadInitialIfNeeded()

        #expect(vm.bannerItems.map(\.id) == [10, 11, 12, 13, 14])
        #expect(store.load().map(\.id) == [10, 11, 12, 13, 14])
    }

    @Test("trending success with same top five ids keeps cached banner")
    func trendingSameIDsKeepsCache() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-vm-banner-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HomeBannerStore(fileURL: url)
        let old = (1...5).map { Self.makeItem(id: $0, name: "old\($0)") }
        #expect(store.updateIfNeeded(from: old) == true)

        let api = FakeBangumiAPI()
        api.trendingResult = .success((1...5).map { Self.makeItem(id: $0, name: "new\($0)") })
        let vm = HomeViewModel(api: api, bannerStore: store)
        await vm.loadInitialIfNeeded()
        await vm.loadSectionIfNeeded(HomeSection.trending.id)

        #expect(vm.bannerItems.map(\.id) == [1, 2, 3, 4, 5])
        #expect(vm.bannerItems.first?.displayName == "old1")
    }

    @Test("setActiveBannerIndex clamps to range")
    func setActiveBannerIndexClamps() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-vm-banner-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HomeBannerStore(fileURL: url)
        #expect(store.updateIfNeeded(from: (1...3).map { Self.makeItem(id: $0, name: "B\($0)") }) == true)

        let vm = HomeViewModel(api: FakeBangumiAPI(), bannerStore: store)
        await vm.loadInitialIfNeeded()
        vm.setActiveBannerIndex(99)
        #expect(vm.activeBannerIndex == 2)
        vm.setActiveBannerIndex(-3)
        #expect(vm.activeBannerIndex == 0)
    }
}
