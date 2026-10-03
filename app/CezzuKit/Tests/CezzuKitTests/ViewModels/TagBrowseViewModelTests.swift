import Foundation
import Testing
@testable import CezzuKit

@Suite("TagBrowseViewModel")
@MainActor
struct TagBrowseViewModelTests {
    private typealias FakeAPI = HomeViewModelTests.FakeBangumiAPI

    private static func makeItem(id: Int, name: String) -> BangumiItem {
        HomeViewModelTests.makeItem(id: id, name: name)
    }

    @Test("empty tag uses 热门番组 title and trending API")
    func trendingTitleAndFetch() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A"), Self.makeItem(id: 2, name: "B")])
        let vm = TagBrowseViewModel(api: api, tag: "")

        #expect(vm.title == "热门番组")
        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(api.trendingCalls == 1)
        #expect(vm.items.count == 2)
        #expect(vm.items[0].id == 1)
        #expect(vm.isLoading == false)
        #expect(vm.loadFailed == false)
    }

    @Test("non-empty tag uses tag as title and search API")
    func taggedTitleAndFetch() async {
        let api = FakeAPI()
        api.searchResult = .success([
            Self.makeItem(id: 100, name: "K1"),
            Self.makeItem(id: 101, name: "K2"),
        ])
        let vm = TagBrowseViewModel(api: api, tag: "治愈")

        #expect(vm.title == "治愈")
        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(api.searchCalls == ["治愈"])
        #expect(vm.items.count == 2)
        #expect(vm.currentTagMatches("治愈"))
    }

    @Test("loadInitialIfNeeded skips when items already loaded")
    func loadInitialSkipsWhenLoaded() async {
        let api = FakeAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A")])
        let vm = TagBrowseViewModel(api: api, tag: "")

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()
        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(api.trendingCalls == 1)
    }

    @Test("API failure sets loadFailed and clears items")
    func failureSetsErrorState() async {
        let api = FakeAPI()
        api.trendingResult = .failure(.http(status: 500))
        let vm = TagBrowseViewModel(api: api, tag: "")

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(vm.loadFailed == true)
        #expect(vm.items.isEmpty)
        #expect(vm.lastError == .http(status: 500))
        #expect(vm.isLoading == false)
    }

    @Test("loadMoreIfNeeded appends next trending page")
    func loadMoreAppendsTrendingPage() async {
        let api = FakeAPI()
        api.trendingResult = .success((1...24).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = TagBrowseViewModel(api: api, tag: "")

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        api.trendingResult = .success((25...30).map { Self.makeItem(id: $0, name: "Item \($0)") })
        await vm.loadMoreIfNeeded(currentItem: vm.items[23])

        #expect(vm.items.count == 30)
        #expect(vm.items.last?.id == 30)
        #expect(vm.isLoadingMore == false)
        #expect(vm.hasMore == false)
        #expect(api.trendingCalls == 2)
    }

    @Test("loadMoreIfNeeded appends tagged page after full first page")
    func loadMoreAppendsTaggedPage() async {
        let api = FakeAPI()
        api.searchResult = .success((1...20).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = TagBrowseViewModel(api: api, tag: "日常")

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        api.searchResult = .success((21...25).map { Self.makeItem(id: $0, name: "Item \($0)") })
        await vm.loadMoreIfNeeded(currentItem: vm.items[19])

        #expect(vm.items.count == 25)
        #expect(vm.items.last?.id == 25)
        #expect(vm.hasMore == false)
        #expect(api.searchCalls == ["日常", "日常"])
        #expect(api.searchOffsets == [0, 20])
    }

    @Test("loadMoreIfNeeded ignores non-last items")
    func loadMoreIgnoresNonLast() async {
        let api = FakeAPI()
        api.searchResult = .success((1...20).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = TagBrowseViewModel(api: api, tag: "校园")

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()
        await vm.loadMoreIfNeeded(currentItem: vm.items[0])

        #expect(vm.items.count == 20)
        #expect(api.searchCalls == ["校园"])
    }
}

// MARK: - Test helpers

@MainActor
extension TagBrowseViewModel {
    func waitForIdle() async {
        while isLoading {
            await Task.yield()
        }
        await Task.yield()
    }

    func currentTagMatches(_ expected: String) -> Bool {
        tag == expected
    }
}
