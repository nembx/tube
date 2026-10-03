import Testing
@testable import CezzuKit

@Suite("Episode pagination")
struct EpisodePaginationTests {
    @Test("每 100 集切一段，最后一段不满也算一段")
    func pageCountRoundsUp() {
        #expect(EpisodePagination.pageCount(episodeCount: 0) == 1)
        #expect(EpisodePagination.pageCount(episodeCount: 1) == 1)
        #expect(EpisodePagination.pageCount(episodeCount: 100) == 1)
        #expect(EpisodePagination.pageCount(episodeCount: 101) == 2)
        #expect(EpisodePagination.pageCount(episodeCount: 1200) == 12)
    }

    @Test("正在播的那一集落在它自己那一段里")
    func pageContainsCurrentEpisode() {
        // 第 1178 集（下标 1177）属于 1101-1200 这一段。
        #expect(EpisodePagination.page(containing: 1177, episodeCount: 1200) == 11)
        #expect(EpisodePagination.page(containing: 0, episodeCount: 1200) == 0)
        #expect(EpisodePagination.page(containing: 99, episodeCount: 1200) == 0)
        #expect(EpisodePagination.page(containing: 100, episodeCount: 1200) == 1)
    }

    @Test("越界的集数下标不会指向不存在的分段")
    func pageClampsOutOfRangeIndex() {
        #expect(EpisodePagination.page(containing: -5, episodeCount: 120) == 0)
        #expect(EpisodePagination.page(containing: 9999, episodeCount: 120) == 1)
        #expect(EpisodePagination.page(containing: 3, episodeCount: 0) == 0)
    }

    @Test("分段的下标区间截到实际集数为止")
    func rangeStopsAtEpisodeCount() {
        #expect(EpisodePagination.range(page: 0, episodeCount: 250) == 0..<100)
        #expect(EpisodePagination.range(page: 2, episodeCount: 250) == 200..<250)
        #expect(EpisodePagination.range(page: 0, episodeCount: 0) == 0..<0)
    }

    @Test("越界的分段号退回到最后一段")
    func rangeClampsOutOfRangePage() {
        #expect(EpisodePagination.range(page: 99, episodeCount: 250) == 200..<250)
        #expect(EpisodePagination.range(page: -1, episodeCount: 250) == 0..<100)
    }
}
