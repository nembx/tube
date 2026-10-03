import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("HomeHeroBanner")
struct HomeHeroBannerLayoutTests {

    @Test("yearString extracts YYYY from airDate")
    func yearFromFullDate() {
        #expect(HomeHeroBannerLayout.yearString(from: "2024-09-29") == "2024")
        #expect(HomeHeroBannerLayout.yearString(from: "2026") == "2026")
    }

    @Test("yearString rejects empty and invalid")
    func yearInvalid() {
        #expect(HomeHeroBannerLayout.yearString(from: "") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "  ") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "abcd") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "0000-01-01") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "20") == nil)
    }

    @Test("layout constants are positive")
    func layoutConstants() {
        #expect(abs(HomeHeroBannerLayout.viewportHeightRatio - 0.56) < 0.0001)
        #expect(HomeHeroBannerLayout.minHeight > 0)
        #expect(HomeHeroBannerLayout.maxTags >= 1)
        #expect(HomeHeroBannerLayout.summaryLineLimit >= 2)
        #expect(HomeHeroBannerLayout.scrimStart > 0)
        #expect(HomeHeroBannerLayout.scrimStart < 0.6)
    }

    @Test("contentHeight follows viewport ratio")
    func contentHeightRatio() {
        let viewport: CGFloat = 800
        let content = HomeHeroBannerLayout.contentHeight(viewportHeight: viewport)
        #expect(abs(content - viewport * HomeHeroBannerLayout.viewportHeightRatio) < 0.001)
    }

    @Test("imageHeight is a fraction of total height, leaving a solid strip below")
    func imageHeightFraction() {
        let total: CGFloat = 480
        let image = HomeHeroBannerLayout.imageHeight(totalHeight: total)
        #expect(abs(image - total * HomeHeroBannerLayout.imageHeightRatio) < 0.001)
        #expect(image < total)
        #expect(image > total * 0.5)
    }

    @Test("contentHeight respects minimum")
    func contentHeightMinimum() {
        let tiny = HomeHeroBannerLayout.contentHeight(viewportHeight: 100)
        #expect(tiny == HomeHeroBannerLayout.minHeight)
    }

    @Test("heatText abbreviates thousands")
    func heatFormatting() {
        #expect(HomeHeroBannerLayout.heatText(0) == "0")
        #expect(HomeHeroBannerLayout.heatText(999) == "999")
        #expect(HomeHeroBannerLayout.heatText(1000) == "1.0k")
        #expect(HomeHeroBannerLayout.heatText(9986) == "10.0k")
        #expect(HomeHeroBannerLayout.heatText(2243) == "2.2k")
    }

    @Test("yearString(fromInfo:) pulls the year out of the trending info string")
    func yearFromInfo() {
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "14话 / 2026年7月4日 / 渋谷亮介") == "2026")
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "木村拓 / 松浦力") == nil)
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "") == nil)
    }

    /// trending 条目没有 summary / tags / date，只有 info + metaTags。
    @Test("factTexts uses metaTags and info year for trending items")
    func factTextsForTrendingItem() {
        let item = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "", rank: 0,
            ratingScore: 7.1, images: .empty, tags: [],
            info: "2026年7月2日 / 木村拓", metaTags: ["TV", "日本", "漫画改", "搞笑"]
        )
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        #expect(facts.first == "2026")
        // metaTags 被截到 maxTags 条
        #expect(facts.count == 1 + HomeHeroBannerLayout.maxTags)
        #expect(facts.contains("漫画改"))
    }

    /// 详情接口的条目有 airDate 和用户 tags，metaTags 为空时要回落。
    @Test("factTexts falls back to user tags when metaTags are absent")
    func factTextsFallsBackToTags() {
        let item = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "2024-09-29", rank: 0,
            ratingScore: 0, images: .empty,
            tags: [BangumiTag(name: "奇幻", count: 10), BangumiTag(name: "冒险", count: 5)]
        )
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        #expect(facts == ["2024", "奇幻", "冒险"])
    }

    @Test("factTexts is empty when the item carries no date or tags")
    func factTextsEmpty() {
        let bare = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: []
        )
        #expect(HomeHeroBannerLayout.factTexts(for: bare).isEmpty)
    }

    @Test("detailText prefers summary and falls back to trending info")
    func detailTextFallback() {
        let withSummary = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "  完整简介  ", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [], info: "12话 / 2026年"
        )
        #expect(HomeHeroBannerLayout.detailText(for: withSummary) == "完整简介")

        let infoOnly = BangumiItem(
            id: 2, name: "B", nameCn: "乙", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [], info: "12话 / 2026年"
        )
        #expect(HomeHeroBannerLayout.detailText(for: infoOnly) == "12话 / 2026年")

        let neither = BangumiItem(
            id: 3, name: "C", nameCn: "丙", summary: "   ", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: []
        )
        #expect(HomeHeroBannerLayout.detailText(for: neither).isEmpty)
    }

    // MARK: - 分页视差

    @Test("imageOverscanWidth leaves room on both sides for the parallax shift")
    func overscanCoversParallaxShift() {
        let page: CGFloat = 390
        let overscan = HomeHeroBannerLayout.imageOverscanWidth(pageWidth: page)
        // 图两侧各多出的量，必须 ≥ 最大位移，否则滑到 ±1 页时会露空边
        let slack = (overscan - page) / 2
        let maxShift = abs(HomeHeroBannerLayout.parallaxOffset(progress: 1, pageWidth: page))
        #expect(slack >= maxShift - 0.001)
        #expect(HomeHeroBannerLayout.imageOverscanWidth(pageWidth: 0) == 0)
        #expect(HomeHeroBannerLayout.imageOverscanWidth(pageWidth: -100) == 0)
    }

    @Test("parallaxOffset is zero on the centred page and moves opposite the page")
    func parallaxDirection() {
        let page: CGFloat = 400
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: 0, pageWidth: page) == 0)
        // 下一页（progress > 0）在右侧，图要往左偏，落后于页面
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: 1, pageWidth: page) < 0)
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: -1, pageWidth: page) > 0)
        let half = HomeHeroBannerLayout.parallaxOffset(progress: 0.5, pageWidth: page)
        let full = HomeHeroBannerLayout.parallaxOffset(progress: 1, pageWidth: page)
        #expect(abs(half * 2 - full) < 0.001)
    }

    @Test("parallaxOffset clamps out-of-range progress and degenerate widths")
    func parallaxEdgeCases() {
        let page: CGFloat = 400
        let atEdge = HomeHeroBannerLayout.parallaxOffset(progress: 1, pageWidth: page)
        // 橡皮筋过滚会让 progress 越过 ±1，位移不能跟着无限增长
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: 4.2, pageWidth: page) == atEdge)
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: -9, pageWidth: page) == -atEdge)
        #expect(HomeHeroBannerLayout.parallaxOffset(progress: 0.5, pageWidth: 0) == 0)
    }

    @Test("dominantIndex flips at the half-page mark")
    func dominantIndexHalfPage() {
        let page: CGFloat = 400
        let count = 5
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 0, pageWidth: page, pageCount: count) == 0)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 199, pageWidth: page, pageCount: count) == 0)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 200, pageWidth: page, pageCount: count) == 1)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 800, pageWidth: page, pageCount: count) == 2)
    }

    @Test("dominantIndex survives rubber-band overscroll and empty carousels")
    func dominantIndexEdgeCases() {
        let page: CGFloat = 400
        // 首尾橡皮筋会给出负偏移 / 超出末页的偏移，不能算出越界下标
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: -120, pageWidth: page, pageCount: 5) == 0)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 9_999, pageWidth: page, pageCount: 5) == 4)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 200, pageWidth: 0, pageCount: 5) == 0)
        #expect(HomeHeroBannerLayout.dominantIndex(scrollOffset: 200, pageWidth: page, pageCount: 0) == 0)
    }

    // MARK: - 无限循环

    @Test("loopedSlotCount triples the items, but only when looping makes sense")
    func loopSlotCount() {
        #expect(HomeHeroBannerLayout.loopedSlotCount(itemCount: 5) == 15)
        #expect(HomeHeroBannerLayout.loopedSlotCount(itemCount: 1) == 1)
        #expect(HomeHeroBannerLayout.loopedSlotCount(itemCount: 0) == 0)
        #expect(HomeHeroBannerLayout.loopedSlotCount(itemCount: -3) == 0)
    }

    @Test("loopStartSlot lands in the middle segment")
    func loopStart() {
        #expect(HomeHeroBannerLayout.loopStartSlot(itemCount: 5, activeIndex: 0) == 5)
        #expect(HomeHeroBannerLayout.loopStartSlot(itemCount: 5, activeIndex: 3) == 8)
        // 越界 activeIndex（缓存条目数缩水时会出现）不能算出段外槽位
        #expect(HomeHeroBannerLayout.loopStartSlot(itemCount: 5, activeIndex: 99) == 9)
        #expect(HomeHeroBannerLayout.loopStartSlot(itemCount: 5, activeIndex: -2) == 5)
        #expect(HomeHeroBannerLayout.loopStartSlot(itemCount: 1, activeIndex: 0) == 0)
    }

    @Test("realIndex maps every segment back onto the items")
    func realIndexMapping() {
        for slot in 0..<15 {
            #expect(HomeHeroBannerLayout.realIndex(slot: slot, itemCount: 5) == slot % 5)
        }
        #expect(HomeHeroBannerLayout.realIndex(slot: 0, itemCount: 0) == 0)
    }

    @Test("recenteredSlot moves outer segments home and leaves the middle alone")
    func recenter() {
        // 中段 5..<10 原地不动
        for slot in 5..<10 {
            #expect(HomeHeroBannerLayout.recenteredSlot(slot: slot, itemCount: 5) == nil)
        }
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 0, itemCount: 5) == 5)
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 4, itemCount: 5) == 9)
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 10, itemCount: 5) == 5)
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 14, itemCount: 5) == 9)
        // 搬迁后的槽位必须是不动点，否则会来回搬
        let target = HomeHeroBannerLayout.recenteredSlot(slot: 14, itemCount: 5)!
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: target, itemCount: 5) == nil)
        // 单页 / 空列表不循环，永不搬迁
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 0, itemCount: 1) == nil)
        #expect(HomeHeroBannerLayout.recenteredSlot(slot: 0, itemCount: 0) == nil)
    }

    @Test("pageBarWeight peaks on the current page and wraps around the ends")
    func pageBarHighlight() {
        #expect(abs(HomeHeroBannerLayout.pageBarWeight(position: 2, index: 2, itemCount: 5) - 1) < 0.001)
        #expect(HomeHeroBannerLayout.pageBarWeight(position: 2, index: 0, itemCount: 5) == 0)
        // 拖到两页之间：两条各分一半
        let a = HomeHeroBannerLayout.pageBarWeight(position: 2.5, index: 2, itemCount: 5)
        let b = HomeHeroBannerLayout.pageBarWeight(position: 2.5, index: 3, itemCount: 5)
        #expect(abs(a - 0.5) < 0.001)
        #expect(abs(b - 0.5) < 0.001)
        // 末页往下一页滑时高亮绕回第一条，而不是横穿整排
        let last = HomeHeroBannerLayout.pageBarWeight(position: 4.5, index: 4, itemCount: 5)
        let first = HomeHeroBannerLayout.pageBarWeight(position: 4.5, index: 0, itemCount: 5)
        #expect(abs(last - 0.5) < 0.001)
        #expect(abs(first - 0.5) < 0.001)
        // 第二、三段的位置要落到与中段相同的高亮
        #expect(abs(HomeHeroBannerLayout.pageBarWeight(position: 12, index: 2, itemCount: 5) - 1) < 0.001)
        #expect(HomeHeroBannerLayout.pageBarWeight(position: 2, index: 0, itemCount: 0) == 0)
    }

    @Test("totalHeight matches content height without stacking top inset")
    func totalHeightMatchesContent() {
        let viewport: CGFloat = 800
        let content = HomeHeroBannerLayout.contentHeight(viewportHeight: viewport)
        let bare = HomeHeroBannerLayout.totalHeight(viewportHeight: viewport, topInset: 0)
        let withTop = HomeHeroBannerLayout.totalHeight(viewportHeight: viewport, topInset: 59)
        #expect(abs(bare - content) < 0.001)
        #expect(abs(withTop - bare) < 0.001)
    }
}
