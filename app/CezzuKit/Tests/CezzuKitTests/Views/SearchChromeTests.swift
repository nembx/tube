import Testing
@testable import CezzuKit

@Suite("Search chrome 筛选档位与文案")
struct SearchChromeTests {
    @Test("年份档位按当前年份滚动")
    func yearPresetsFollowCurrentYear() {
        let presets = SearchYearPreset.presets(currentYear: 2026)
        #expect(presets.first?.id == "any")
        let last3 = try! #require(presets.first { $0.id == "last3" })
        #expect(last3.min == 2024)
        #expect(last3.max == 2026)
    }

    @Test("年份标题命中档位时用档位名")
    func yearTitleMatchesPreset() {
        #expect(SearchYearPreset.title(min: nil, max: nil, currentYear: 2026) == "不限")
        #expect(SearchYearPreset.title(min: 2026, max: 2026, currentYear: 2026) == "今年")
        #expect(SearchYearPreset.title(min: 2010, max: 2019, currentYear: 2026) == "2010s")
    }

    @Test("年份标题没命中档位时按区间直述")
    func yearTitleFallsBackToRange() {
        #expect(SearchYearPreset.title(min: 2003, max: 2007, currentYear: 2026) == "2003–2007")
        #expect(SearchYearPreset.title(min: 2003, max: nil, currentYear: 2026) == "2003 年起")
        #expect(SearchYearPreset.title(min: nil, max: 2003, currentYear: 2026) == "2003 年前")
        #expect(SearchYearPreset.title(min: 2003, max: 2003, currentYear: 2026) == "2003")
    }

    @Test("评分标题：0 和 nil 都算不限")
    func ratingTitle() {
        #expect(SearchRatingPreset.title(for: nil) == "不限")
        #expect(SearchRatingPreset.title(for: 0) == "不限")
        #expect(SearchRatingPreset.title(for: 7.5) == "≥ 7.5")
    }

    @Test("没有任何筛选时摘要为空")
    func activeFilterChipsEmpty() {
        let chips = SearchActiveFilter.chips(
            tags: [],
            ratingMin: nil,
            yearMin: nil,
            yearMax: nil,
            currentYear: 2026
        )
        #expect(chips.isEmpty)
    }

    @Test("摘要按标签 → 评分 → 年份排列")
    func activeFilterChipsOrder() {
        let chips = SearchActiveFilter.chips(
            tags: ["科幻", "治愈"],
            ratingMin: 8,
            yearMin: 2020,
            yearMax: 2029,
            currentYear: 2026
        )
        #expect(chips.map(\.title) == ["科幻", "治愈", "≥ 8.0", "2020s"])
        #expect(chips.map(\.kind) == [.tag("科幻"), .tag("治愈"), .rating, .year])
    }

    @Test("摘要忽略 0 分下限，但只给一端年份也算生效")
    func activeFilterChipsEdges() {
        let zeroRating = SearchActiveFilter.chips(
            tags: [],
            ratingMin: 0,
            yearMin: nil,
            yearMax: nil,
            currentYear: 2026
        )
        #expect(zeroRating.isEmpty)

        let openEndedYear = SearchActiveFilter.chips(
            tags: [],
            ratingMin: nil,
            yearMin: nil,
            yearMax: 1989,
            currentYear: 2026
        )
        #expect(openEndedYear.map(\.title) == ["更早"])
    }

    @Test("结果计数：有关键词时带上关键词，还有下一页时加 +")
    func resultsSummary() {
        #expect(SearchResultsSummary.text(count: 20, hasMore: true, keyword: "轻音") == "“轻音” · 20+ 条结果")
        #expect(SearchResultsSummary.text(count: 3, hasMore: false, keyword: "轻音") == "“轻音” · 3 条结果")
    }

    @Test("结果计数：只按筛选搜（关键词空白）时不显示空引号")
    func resultsSummaryWithoutKeyword() {
        #expect(SearchResultsSummary.text(count: 0, hasMore: false, keyword: "   ") == "共 0 条结果")
        #expect(SearchResultsSummary.text(count: 40, hasMore: true, keyword: "") == "共 40+ 条结果")
    }
}
