import Testing
@testable import TubeKit

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {

    private static func makeItem(id: Int, name: String) -> BangumiItem {
        BangumiItem(
            id: id,
            name: name,
            nameCn: name,
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
    }

    @Test("submit searches Bangumi with selected sort")
    func submitUsesSelectedSort() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([
            Self.makeItem(id: 1, name: "Frieren")
        ])
        let vm = SearchViewModel(api: api)
        vm.text = "芙莉莲"
        vm.selectedSort = .score

        await vm.submit()

        #expect(vm.results.count == 1)
        #expect(vm.results[0].id == 1)
        #expect(vm.lastError == nil)
        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchCalls[0].0 == "芙莉莲")
        #expect(api.keywordSearchCalls[0].1 == .score)
        #expect(api.keywordSearchCalls[0].2 == 0)
    }

    @Test("loadMoreIfNeeded appends the next Bangumi search page")
    func loadMoreAppendsNextPage() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success((1...20).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = SearchViewModel(api: api)
        vm.text = "机动战士"

        await vm.submit()

        api.keywordSearchResult = .success((21...24).map { Self.makeItem(id: $0, name: "Item \($0)") })
        await vm.loadMoreIfNeeded(currentItem: vm.results[19])

        #expect(vm.results.count == 24)
        #expect(vm.results.last?.id == 24)
        #expect(vm.hasMore == false)
        #expect(api.keywordSearchCalls.count == 2)
        #expect(api.keywordSearchCalls[1].2 == 20)
    }

    @Test("submit records the trimmed keyword to history on success")
    func submitRecordsHistoryOnSuccess() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 1, name: "X")])
        let history = InMemorySearchHistoryStore()
        let vm = SearchViewModel(api: api, history: history)
        vm.text = "  海贼王  "

        await vm.submit()

        #expect(history.recent == ["海贼王"])
    }

    @Test("submit does not record history when the request fails")
    func submitSkipsHistoryOnFailure() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .failure(.timeout)
        let history = InMemorySearchHistoryStore()
        let vm = SearchViewModel(api: api, history: history)
        vm.text = "海贼王"

        await vm.submit()

        #expect(vm.lastError == .timeout)
        #expect(history.recent.isEmpty)
    }

    @Test("submit with only a tag does not write a keyword to history")
    func submitWithOnlyTagSkipsHistory() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let history = InMemorySearchHistoryStore()
        let vm = SearchViewModel(api: api, history: history)
        vm.applyTag("校园")

        await vm.submit()

        #expect(api.keywordSearchCalls.count == 1)
        #expect(history.recent.isEmpty)
    }

    @Test("textChanged debounces and triggers submit when keyword crosses min length")
    func textChangedDebouncesAndSubmits() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 7, name: "X")])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)

        vm.text = "海贼王"
        vm.textChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchCalls[0].0 == "海贼王")
        #expect(vm.results.count == 1)
    }

    @Test("textChanged ignores keywords shorter than the minimum length")
    func textChangedIgnoresShortKeyword() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 1, name: "X")])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)

        vm.text = "X"
        vm.textChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.isEmpty)
    }

    @Test("rapid textChanged collapses to a single submit")
    func textChangedCollapsesRapidEdits() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 30)

        vm.text = "海贼"
        vm.textChanged()
        vm.text = "海贼王"
        vm.textChanged()
        vm.text = "海贼王女"
        vm.textChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchCalls[0].0 == "海贼王女")
    }

    @Test("sortChanged re-submits when there is a prior search context")
    func sortChangedResearches() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 1, name: "X")])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)
        vm.text = "海贼王"

        await vm.submit()
        #expect(api.keywordSearchCalls.count == 1)

        vm.selectedSort = .heat
        vm.sortChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.count == 2)
        #expect(api.keywordSearchCalls[1].1 == .heat)
    }

    @Test("sortChanged is a no-op before the first search")
    func sortChangedNoopBeforeFirstSearch() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)

        vm.selectedSort = .heat
        vm.sortChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.isEmpty)
    }

    @Test("applyHistory writes the keyword and submits immediately")
    func applyHistorySubmits() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 1, name: "X")])
        let history = InMemorySearchHistoryStore(seed: ["海贼王"])
        let vm = SearchViewModel(api: api, history: history)

        await vm.applyHistory("海贼王")

        #expect(vm.text == "海贼王")
        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchCalls[0].0 == "海贼王")
    }

    @Test("clearText empties the input and cancels pending debounce")
    func clearTextCancelsDebounce() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 50)

        vm.text = "海贼王"
        vm.textChanged()
        vm.clearText()
        await vm.waitForIdle()

        #expect(vm.text.isEmpty)
        #expect(api.keywordSearchCalls.isEmpty)
    }

    @Test("deleteHistory and clearHistory delegate to the store")
    func historyMutationsDelegate() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        let history = InMemorySearchHistoryStore(seed: ["海贼王", "鬼灭"])
        let vm = SearchViewModel(api: api, history: history)

        vm.deleteHistory("海贼王")
        #expect(vm.historyKeywords == ["鬼灭"])

        vm.clearHistory()
        #expect(vm.historyKeywords.isEmpty)
    }

    @Test("bindHistory switches store without resetting search text")
    func bindHistorySwitchesStore() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([Self.makeItem(id: 1, name: "X")])
        let emptyStore = InMemorySearchHistoryStore(seed: ["旧"])
        let persistentStore = InMemorySearchHistoryStore()
        let vm = SearchViewModel(api: api, history: emptyStore)
        vm.text = "海贼王"
        #expect(vm.historyKeywords == ["旧"])

        // 模拟 iOS Root：empty session → persistent session 后重绑
        vm.bindHistory(persistentStore)
        #expect(vm.historyKeywords.isEmpty)
        #expect(vm.text == "海贼王")

        await vm.submit()
        #expect(persistentStore.recent == ["海贼王"])
        #expect(emptyStore.recent == ["旧"])
    }

    @Test("submit forwards advanced filter into the request")
    func submitForwardsAdvancedFilter() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api)
        vm.text = "海贼王"
        vm.selectedTags = ["校园", "原创"]
        vm.ratingMin = 8.0
        vm.yearMin = 2020
        vm.yearMax = 2023

        await vm.submit()

        #expect(api.keywordSearchFilters.count == 1)
        let f = api.keywordSearchFilters[0]
        #expect(f.tags == ["校园", "原创"])
        #expect(f.ratingMin == 8.0)
        #expect(f.airDateAfter == "2020-01-01")
        #expect(f.airDateBefore == "2024-01-01")
        #expect(f.includeNSFW == true)
    }

    @Test("addTag dedupes and preserves insertion order")
    func addTagDedupes() {
        let api = HomeViewModelTests.FakeBangumiAPI()
        let vm = SearchViewModel(api: api)
        vm.addTag("校园")
        vm.addTag("原创")
        vm.addTag("  校园  ")
        vm.addTag("")

        #expect(vm.selectedTags == ["校园", "原创"])
    }

    @Test("removeTag triggers an immediate research when there is context")
    func removeTagResearches() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)
        vm.text = "海贼王"
        vm.selectedTags = ["校园", "原创"]
        await vm.submit()

        vm.removeTag("校园")
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.count == 2)
        #expect(api.keywordSearchFilters.last?.tags == ["原创"])
    }

    @Test("resetAdvancedFilter clears all and re-runs the search")
    func resetAdvancedFilterResearches() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)
        vm.text = "海贼王"
        vm.selectedTags = ["校园"]
        vm.ratingMin = 7.5
        await vm.submit()

        vm.resetAdvancedFilter()
        await vm.waitForIdle()

        #expect(vm.selectedTags.isEmpty)
        #expect(vm.ratingMin == nil)
        #expect(api.keywordSearchCalls.count == 2)
        #expect(api.keywordSearchFilters.last?.tags.isEmpty == true)
        #expect(api.keywordSearchFilters.last?.includeNSFW == true)
    }

    @Test("advancedFilterChanged is a no-op when no keyword/filter would be sent")
    func advancedFilterChangedNoopWithoutContext() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)

        vm.advancedFilterChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.isEmpty)
    }

    @Test("textChanged triggers even when keyword is short but filter is active")
    func textChangedRespectsActiveFilter() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([])
        let vm = SearchViewModel(api: api, debounceMilliseconds: 5)
        vm.selectedTags = ["校园"]

        vm.text = "X"
        vm.textChanged()
        await vm.waitForIdle()

        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchFilters.last?.tags == ["校园"])
    }

    /// 第一页会被补充通道插进额外条目，此时 `results.count` 不等于下一页的 offset。
    /// VM 必须用 page 带回来的游标，否则翻页会跳过若干条结果。
    @Test("paging follows the page cursor, not the rendered result count")
    func pagingUsesPageCursorNotResultCount() async {
        let api = PagingCursorAPI()
        let vm = SearchViewModel(api: api)
        vm.text = "受限条目"

        await vm.submit()
        // 21 条 = 20 条主结果 + 1 条补充通道插入的。
        #expect(vm.results.count == 21)
        #expect(vm.hasMore)

        await vm.loadMoreIfNeeded(currentItem: vm.results[20])
        #expect(api.offsets == [0, 20])
    }

    /// 第一页返回的条目数多于游标推进量，模拟补充通道的插入。
    private final class PagingCursorAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        private(set) var offsets: [Int] = []

        static func item(id: Int, name: String) -> BangumiItem {
            BangumiItem(
                id: id, name: name, nameCn: name, summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            )
        }

        func searchPage(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            limit: Int,
            offset: Int
        ) async throws -> BangumiSearchPage {
            offsets.append(offset)
            let promoted = offset == 0 ? [Self.item(id: 999, name: "受限条目")] : []
            let regular = (1...limit).map { Self.item(id: offset + $0, name: "Item \($0)") }
            return BangumiSearchPage(
                items: promoted + regular,
                nextOffset: offset + regular.count,
                hasMore: true
            )
        }

        func search(
            keyword: String, sort: BangumiSearchSort, filter: BangumiSearchFilter,
            limit: Int, offset: Int
        ) async throws -> [BangumiItem] {
            try await searchPage(
                keyword: keyword, sort: sort, filter: filter, limit: limit, offset: offset
            ).items
        }

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            throw BangumiAPIError.http(status: 404)
        }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { [] }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { [] }
    }

    @Test("selectedTag setter mirrors a single-tag selectedTags")
    func selectedTagBackCompat() {
        let api = HomeViewModelTests.FakeBangumiAPI()
        let vm = SearchViewModel(api: api)
        vm.selectedTag = "校园"
        #expect(vm.selectedTags == ["校园"])
        vm.selectedTag = nil
        #expect(vm.selectedTags.isEmpty)
    }
}
