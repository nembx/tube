import Foundation
import Testing

@testable import TubeKit

@Suite("TitleMatcher")
struct TitleMatcherTests {

    @Test("season defaults to 1 when the title carries no season marker")
    func seasonDefaultsToOne() {
        #expect(TitleMatcher.season(of: "药屋少女的呢喃") == 1)
        #expect(TitleMatcher.season(of: "Sousou no Frieren") == 1)
        #expect(TitleMatcher.season(of: "") == 1)
    }

    @Test("season reads Chinese, arabic, roman and english markers")
    func seasonReadsCommonMarkers() {
        #expect(TitleMatcher.season(of: "药屋少女的呢喃 第三季") == 3)
        #expect(TitleMatcher.season(of: "药屋少女的呢喃 第2季") == 2)
        #expect(TitleMatcher.season(of: "凡人修仙传 第十二季") == 12)
        #expect(TitleMatcher.season(of: "某番 第二期") == 2)
        #expect(TitleMatcher.season(of: "葬送的芙莉莲 II") == 2)
        #expect(TitleMatcher.season(of: "葬送的芙莉莲Ⅲ") == 3)
        #expect(TitleMatcher.season(of: "Frieren Season 2") == 2)
        #expect(TitleMatcher.season(of: "Frieren 2nd Season") == 2)
        #expect(TitleMatcher.season(of: "Frieren S2") == 2)
    }

    /// 「第2部分」是分割播出，不是季度 —— 不能被当成第二季。
    @Test("season ignores part markers")
    func seasonIgnoresPartMarkers() {
        #expect(TitleMatcher.season(of: "药屋少女的呢喃 第2部分") == 1)
        #expect(TitleMatcher.season(of: "药屋少女的呢喃 第三季 第2部分") == 3)
    }

    private func result(_ title: String, _ path: String) -> SearchResult {
        SearchResult(
            title: title,
            detailURL: URL(string: "https://site.example/\(path)")!,
            ruleName: "R"
        )
    }

    /// 季度对不上的源不再被丢弃（丢弃会让列表凭空变短），但必须被标出来、排在后面，
    /// 且不会成为自动选中的那一个 —— 这是"显示第三季、播出第一季"的根源。
    @Test("a different season is kept but flagged and ranked last")
    func differentSeasonIsDemotedNotDropped() throws {
        let matches = TitleMatcher.matches(
            in: [result("药屋少女的呢喃", "s1"), result("药屋少女的呢喃 第三季", "s3")],
            keywords: ["药屋少女的呢喃 第三季"],
            expectedSeason: 3
        )
        #expect(matches.count == 2)
        let first = try #require(matches.first)
        #expect(first.result.detailURL.lastPathComponent == "s3")
        #expect(first.seasonMatches)
        let last = try #require(matches.last)
        #expect(last.result.detailURL.lastPathComponent == "s1")
        #expect(last.seasonMatches == false)
        #expect(last.season == 1)
    }

    /// 关键词里既有去了季号的基名也有不带季号的别名；季度只认条目自身的季度，
    /// 否则基名关键词会让站点的第一季伪装成命中。
    @Test("the expected season wins over whatever the keyword spells")
    func expectedSeasonOverridesKeywordSpelling() throws {
        // 基名关键词（不带季号）不该让站点的第一季被当成第三季
        let byBaseName = TitleMatcher.matches(
            in: [result("药屋少女的呢喃", "s1")],
            keywords: ["药屋少女的呢喃"],
            expectedSeason: 3
        )
        #expect(byBaseName.first?.seasonMatches == false)

        // 反过来，别名（不带季号）要能命中第三季的站点标题
        let byAlias = TitleMatcher.matches(
            in: [result("药师少女的独语 第三季", "alias-s3")],
            keywords: ["药师少女的独语"],
            expectedSeason: 3
        )
        #expect(byAlias.first?.seasonMatches == true)
    }

    @Test("expectedSeason reads whichever of the two names carries a marker")
    func expectedSeasonReadsEitherName() {
        #expect(TitleMatcher.expectedSeason(displayName: "药屋少女的呢喃 第三季", name: "Kusuriya") == 3)
        #expect(TitleMatcher.expectedSeason(displayName: "药屋少女的呢喃", name: "Kusuriya 3rd Season") == 3)
        #expect(TitleMatcher.expectedSeason(displayName: "葬送的芙莉莲", name: "Sousou no Frieren") == 1)
    }

    @Test("score measures how tightly the titles overlap, season aside")
    func scoreMeasuresOverlap() {
        #expect(TitleMatcher.score(title: "药屋少女的呢喃", keyword: "药屋少女的呢喃") == 3)
        #expect(TitleMatcher.score(title: "药屋少女的呢喃 无删减版", keyword: "药屋少女的呢喃") == 2)
        #expect(TitleMatcher.score(title: "药屋少女", keyword: "药屋少女的呢喃") == 1)
        // 季号写法不同但基名相同，重合度照样满分
        #expect(TitleMatcher.score(title: "药屋少女的呢喃Ⅲ", keyword: "药屋少女的呢喃 第三季") == 3)
    }

    @Test("unrelated titles score zero and never enter the list")
    func unrelatedTitlesScoreZero() {
        #expect(TitleMatcher.score(title: "快把我哥带走", keyword: "药屋少女的呢喃") == 0)
        #expect(TitleMatcher.score(title: "", keyword: "药屋少女的呢喃") == 0)
        #expect(
            TitleMatcher.matches(
                in: [result("快把我哥带走", "x")],
                keywords: ["药屋少女的呢喃"],
                expectedSeason: 1
            ).isEmpty
        )
    }

    /// 名字完全对不上的一个都不留；季度对不上的不算"对不上"，它还在列表里。
    @Test("bestMatch returns nil only when no title matches by name")
    func bestMatchRejectsZeroScores() {
        #expect(
            TitleMatcher.bestMatch(
                in: [result("快把我哥带走", "a"), result("异世界药局", "b")],
                keywords: ["药屋少女的呢喃 第三季"],
                expectedSeason: 3
            ) == nil
        )
        // 只有上一季时仍然返回它，但标着 seasonMatches = false
        let fallback = TitleMatcher.bestMatch(
            in: [result("药屋少女的呢喃", "s1")],
            keywords: ["药屋少女的呢喃 第三季"],
            expectedSeason: 3
        )
        #expect(fallback?.seasonMatches == false)
    }

    @Test("strippingSeason keeps the original spelling of the base title")
    func strippingSeasonKeepsSpelling() {
        #expect(TitleMatcher.strippingSeason("药屋少女的呢喃 第三季") == "药屋少女的呢喃")
        #expect(TitleMatcher.strippingSeason("Kusuriya no Hitorigoto 2nd Season") == "Kusuriya no Hitorigoto")
        #expect(TitleMatcher.strippingSeason("葬送的芙莉莲") == "葬送的芙莉莲")
    }

    @Test("splitAliases splits on the separators Bangumi and sites actually use")
    func splitAliasesHandlesSeparators() {
        #expect(
            TitleMatcher.splitAliases("药师少女的独语、Kusuriya no Hitorigoto、The Apothecary Diaries")
                == ["药师少女的独语", "Kusuriya no Hitorigoto", "The Apothecary Diaries"]
        )
        #expect(TitleMatcher.splitAliases("甲 / 乙／丙") == ["甲", "乙", "丙"])
        #expect(TitleMatcher.splitAliases("").isEmpty)
    }

    /// 别名多的条目要能把它们全用上 —— 默认上限不能低到把别名挤掉。
    @Test("searchKeywords keeps the aliases that fit under the default limit")
    func searchKeywordsKeepsAliasesByDefault() {
        let keywords = TitleMatcher.searchKeywords(
            displayName: "药屋少女的呢喃 第三季",
            name: "Kusuriya no Hitorigoto 3rd Season",
            aliases: ["药师少女的独语", "The Apothecary Diaries", "薬屋のひとりごと", "猫猫的呢喃"]
        )
        #expect(keywords.count == 7)
        #expect(keywords.contains("猫猫的呢喃"))
    }

    @Test("searchKeywords adds the season-stripped base name and the aliases")
    func searchKeywordsExpandsCandidates() {
        let keywords = TitleMatcher.searchKeywords(
            displayName: "药屋少女的呢喃 第三季",
            name: "Kusuriya no Hitorigoto 3rd Season",
            aliases: ["药师少女的独语", "The Apothecary Diaries"]
        )
        #expect(keywords.first == "药屋少女的呢喃 第三季")
        #expect(keywords.contains("药屋少女的呢喃"))
        #expect(keywords.contains("药师少女的独语"))
    }

    /// 关键词会和每条规则做笛卡尔积并发请求，必须去重且限量。
    @Test("searchKeywords dedupes and respects the limit")
    func searchKeywordsDedupesAndCaps() {
        let keywords = TitleMatcher.searchKeywords(
            displayName: "葬送的芙莉莲",
            name: "葬送的芙莉莲",
            aliases: ["葬送的芙莉莲", "Frieren", "Sousou no Frieren", "芙莉莲", "送葬的芙莉莲"],
            limit: 3
        )
        #expect(keywords == ["葬送的芙莉莲", "Frieren", "Sousou no Frieren"])
    }

    @Test("bestMatch picks the highest score across every keyword")
    func bestMatchPicksHighestAcrossKeywords() throws {
        let loose = SearchResult(
            title: "药屋少女的呢喃 第三季 无删减",
            detailURL: URL(string: "https://site.example/loose")!,
            ruleName: "R"
        )
        let exact = SearchResult(
            title: "Kusuriya no Hitorigoto III",
            detailURL: URL(string: "https://site.example/exact")!,
            ruleName: "R"
        )
        let match = try #require(
            TitleMatcher.bestMatch(
                in: [loose, exact],
                keywords: ["药屋少女的呢喃 第三季", "Kusuriya no Hitorigoto III"],
                expectedSeason: 3
            )
        )
        #expect(match.result == exact)
        #expect(match.score == 3)
    }
    /// Bangumi 会把标题里的敏感字打码成「〇」，资源站用的是原字。差这一个字，
    /// 纯包含匹配就判 0 分，整条源被丢掉 —— 条目搜得到却一个播放源都没有。
    @Test("a censorship mask matches the real character behind it")
    func maskMatchesRealCharacter() {
        let siteTitle = "泡在我家的辣妹同意让我使用她的小穴"
        let bangumiName = "泡在我家的辣妹同意让我使用她的〇穴"
        #expect(TitleMatcher.score(title: siteTitle, keyword: bangumiName) == 3)
    }

    /// 掩码在站点一侧同样要能对上。
    @Test("the mask works from either side")
    func maskWorksFromEitherSide() {
        #expect(TitleMatcher.score(title: "某〇片名", keyword: "某A片名") == 3)
    }

    /// 掩码只顶一个字，不是通配整段 —— 否则不同的番会互相错配。
    @Test("a mask stands for exactly one character")
    func maskCoversOneCharacterOnly() {
        #expect(TitleMatcher.score(title: "某AB片名", keyword: "某〇片名") == 0)
    }

    /// 掩码不能把两部真正不同的片子拉到一起。
    @Test("masks do not collapse genuinely different titles")
    func masksDoNotOverMatch() {
        #expect(TitleMatcher.score(title: "间谍过家家", keyword: "咒术回战") == 0)
        #expect(TitleMatcher.score(title: "〇〇〇", keyword: "咒术回战") == 0)
    }

    /// 掩码顶替的字数不能超过总长的四分之一，否则短标题会被掩码吃穿。
    @Test("masks may cover at most a quarter of the title")
    func maskDensityIsCapped() {
        // 12 字里 3 个掩码 = 25%，仍然算匹配。
        #expect(TitleMatcher.score(title: "abcdefghijkl", keyword: "〇〇〇defghijkl") == 3)
        // 再多一个就超了。
        #expect(TitleMatcher.score(title: "abcdefghijkl", keyword: "〇〇〇〇efghijkl") == 0)
    }

    /// 没有掩码的标题行为必须和以前完全一致。
    @Test("mask support leaves mask-free matching unchanged")
    func maskFreeBehaviourUnchanged() {
        #expect(TitleMatcher.score(title: "孤独摇滚！", keyword: "孤独摇滚！") == 3)
        #expect(TitleMatcher.score(title: "孤独摇滚！剧场版", keyword: "孤独摇滚！") == 2)
        #expect(TitleMatcher.score(title: "孤独摇滚", keyword: "孤独摇滚！剧场版") == 1)
        #expect(TitleMatcher.score(title: "咒术回战", keyword: "间谍过家家") == 0)
    }

}
