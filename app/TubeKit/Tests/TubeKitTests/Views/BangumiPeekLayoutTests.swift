import CoreGraphics
import Testing
@testable import TubeKit

@Suite("BangumiPeek preview")
struct BangumiPeekLayoutTests {

    private func item(
        name: String = "Sousou no Frieren",
        nameCn: String = "葬送的芙莉莲",
        summary: String = "",
        airDate: String = "",
        ratingScore: Double = 0,
        tags: [BangumiTag] = [],
        info: String = "",
        metaTags: [String] = [],
        totalEpisodes: Int = 0,
        eps: Int = 0
    ) -> BangumiItem {
        BangumiItem(
            id: 1, name: name, nameCn: nameCn,
            summary: summary, airDate: airDate, rank: 0, ratingScore: ratingScore,
            images: .empty, tags: tags,
            eps: eps, info: info, metaTags: metaTags, totalEpisodes: totalEpisodes
        )
    }

    @Test("subtitle only shows the original name when it differs from the display name")
    func subtitleSkipsDuplicates() {
        #expect(BangumiPeekLayout.subtitle(for: item()) == "Sousou no Frieren")
        // 没有中文名时 displayName 就是原名，再显示一遍是重复
        #expect(BangumiPeekLayout.subtitle(for: item(nameCn: "Sousou no Frieren")) == nil)
        #expect(BangumiPeekLayout.subtitle(for: item(name: "   ")) == nil)
    }

    @Test("rating is hidden when the item has no score")
    func ratingHiddenWithoutScore() {
        #expect(BangumiPeekLayout.ratingText(for: item(ratingScore: 8.68)) == "8.7")
        #expect(BangumiPeekLayout.ratingText(for: item(ratingScore: 0)) == nil)
    }

    @Test("facts read episodes, year and categories, capped so the card stays one line")
    func factsAreCapped() {
        let full = item(
            airDate: "2023-09-29",
            metaTags: ["TV", "日本", "漫画改", "奇幻"],
            totalEpisodes: 28
        )
        #expect(BangumiPeekLayout.factTexts(for: full) == ["28话", "2023", "TV"])
        #expect(BangumiPeekLayout.factTexts(for: full).count <= BangumiPeekLayout.maxFacts)
    }

    @Test("facts fall back to user tags and to the trending info line")
    func factsFallBack() {
        let trending = item(
            tags: [BangumiTag(name: "奇幻", count: 100)],
            info: "28话 / 2023年9月29日 / 导演",
            eps: 28
        )
        #expect(BangumiPeekLayout.factTexts(for: trending) == ["28话", "2023", "奇幻"])
    }

    @Test("an item with nothing to show produces no facts")
    func factsCanBeEmpty() {
        #expect(BangumiPeekLayout.factTexts(for: item()).isEmpty)
    }

    @Test("summary is flattened to a single paragraph")
    func summaryIsFlattened() {
        let wrapped = item(summary: "  魔法使芙莉莲\n\n与勇者辛美尔一行\t打倒了魔王。  ")
        #expect(
            BangumiPeekLayout.summaryText(for: wrapped)
                == "魔法使芙莉莲 与勇者辛美尔一行 打倒了魔王。"
        )
    }

    @Test("summary falls back to the trending info line, and to nothing at all")
    func summaryFallsBack() {
        #expect(BangumiPeekLayout.summaryText(for: item(info: "28话 / 导演")) == "28话 / 导演")
        #expect(BangumiPeekLayout.summaryText(for: item()).isEmpty)
    }

    @Test("the preview card is narrower than a phone and taller than its cover")
    func previewFitsOnPhone() {
        #expect(BangumiPeekLayout.width <= 320)
        let coverHeight = BangumiPeekLayout.width / BangumiPeekLayout.coverAspectRatio
        #expect(coverHeight > BangumiPeekLayout.width)
        #expect(BangumiPeekLayout.summaryLineLimit > 0)
    }
}
