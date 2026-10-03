import Foundation
import Testing
@testable import CezzuKit

@Suite("RegularHomeViewModel")
@MainActor
struct RegularHomeViewModelTests {
    private typealias FakeAPI = HomeViewModelTests.FakeBangumiAPI

    private static func makeItem(id: Int, name: String) -> BangumiItem {
        HomeViewModelTests.makeItem(id: id, name: name)
    }

    @Test("availableTags 与窄屏 HomeViewModel 对齐")
    func availableTagsShared() {
        #expect(RegularHomeViewModel.availableTags == HomeViewModel.availableTags)
        #expect(!RegularHomeViewModel.availableTags.isEmpty)
    }

    @Test("loadInitialIfNeeded 默认拉热门")
    func loadInitialTrending() async {
        let api = FakeAPI()
        api.trendingResult = .success([
            Self.makeItem(id: 1, name: "A"),
            Self.makeItem(id: 2, name: "B"),
        ])
        let vm = RegularHomeViewModel(api: api)

        await vm.loadInitialIfNeeded()

        #expect(vm.currentTag.isEmpty)
        #expect(vm.items.map(\.id) == [1, 2])
        #expect(api.trendingCalls == 1)
        #expect(api.trendingLimits == [24])
        #expect(!vm.isLoading)
        #expect(!vm.loadFailed)
    }

    @Test("loadInitialIfNeeded 已有数据时不重复请求")
    func loadInitialSkipsWhenLoaded() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A")])
        let vm = RegularHomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.loadInitialIfNeeded()

        #expect(api.trendingCalls == 1)
    }

    @Test("selectTag 切到 tag 搜索并清空旧列表")
    func selectTagSearches() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "Hot")])
        api.searchResultsByTag["日常"] = .success([
            Self.makeItem(id: 10, name: "Daily"),
        ])
        let vm = RegularHomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.selectTag("日常")

        #expect(vm.currentTag == "日常")
        #expect(vm.items.map(\.id) == [10])
        #expect(api.searchCalls == ["日常"])
        #expect(api.searchLimits == [20])
    }

    @Test("selectTag 相同 tag 不发请求")
    func selectSameTagNoop() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "Hot")])
        let vm = RegularHomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.selectTag("")

        #expect(api.trendingCalls == 1)
        #expect(api.searchCalls.isEmpty)
    }

    @Test("reload 失败时标记 loadFailed")
    func reloadFailure() async {
        let api = FakeAPI()
        api.trendingResult = .failure(.transport(message: "offline"))
        let vm = RegularHomeViewModel(api: api)

        await vm.reload()

        #expect(vm.loadFailed)
        #expect(vm.items.isEmpty)
        #expect(vm.lastError != nil)
        #expect(!vm.isLoading)
    }

    @Test("loadMoreIfNeeded 仅在末项触发分页")
    func loadMoreOnLastItem() async {
        let firstPage = (1...24).map { Self.makeItem(id: $0, name: "\($0)") }
        let secondPage = (25...30).map { Self.makeItem(id: $0, name: "\($0)") }
        let api = FakeAPI()
        api.trendingResult = .success(firstPage)
        let vm = RegularHomeViewModel(api: api)

        await vm.reload()
        #expect(vm.hasMore)
        #expect(vm.items.count == 24)

        // 非末项不触发
        await vm.loadMoreIfNeeded(currentItem: firstPage[0])
        #expect(vm.items.count == 24)

        api.trendingResult = .success(secondPage)
        await vm.loadMoreIfNeeded(currentItem: firstPage.last!)
        #expect(vm.items.count == 30)
        #expect(api.trendingCalls == 2)
        // 第二页不足 page size → hasMore = false
        #expect(!vm.hasMore)
    }

    @Test("loadMore 短页后 hasMore 为 false")
    func loadMoreShortPageEnds() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "Only")])
        let vm = RegularHomeViewModel(api: api)

        await vm.reload()
        #expect(!vm.hasMore)
        #expect(vm.items.count == 1)

        await vm.loadMoreIfNeeded(currentItem: vm.items[0])
        #expect(api.trendingCalls == 1)
    }
}
