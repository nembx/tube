import Foundation
import Testing

@testable import CezzuKit

@Suite("SourceGroup")
struct SourceGroupTests {
    private static func scored(
        rule: String,
        title: String,
        path: String,
        score: Int = 3,
        season: Int = 1,
        seasonMatches: Bool = true
    ) -> TitleMatcher.ScoredResult {
        TitleMatcher.ScoredResult(
            result: SearchResult(
                title: title,
                detailURL: URL(string: "https://\(rule).example/\(path)")!,
                ruleName: rule
            ),
            score: score,
            season: season,
            seasonMatches: seasonMatches
        )
    }

    @Test("同一条规则的多个条目合并成一组，组内外都保持 ranked 的顺序")
    func groupsByRuleKeepingOrder() {
        let sources = PlayableSource.ranked([
            Self.scored(rule: "gugu3", title: "从零开始的异世界生活 第四季", path: "s4"),
            Self.scored(rule: "baimao", title: "从零开始的异世界生活", path: "s1", score: 2),
            Self.scored(rule: "gugu3", title: "从零开始的异世界生活", path: "s1", score: 2),
        ])

        let groups = PlayableSource.grouped(sources)

        #expect(groups.map(\.ruleName) == ["gugu3", "baimao"])
        #expect(groups[0].sources.map(\.variantLabel) == [
            "从零开始的异世界生活 第四季",
            "从零开始的异世界生活",
        ])
        #expect(groups[1].sources.count == 1)
        #expect(groups.map(\.id) == ["gugu3", "baimao"])
    }

    @Test("季度对不上的条目在下拉标签里也带季度后缀")
    func variantLabelCarriesSeasonSuffix() {
        let sources = PlayableSource.ranked([
            Self.scored(rule: "AGE", title: "从零开始的异世界生活 第四季", path: "s4"),
            Self.scored(
                rule: "AGE",
                title: "从零开始的异世界生活",
                path: "s1",
                season: 1,
                seasonMatches: false
            ),
        ])

        let group = PlayableSource.grouped(sources)[0]

        #expect(group.sources.count == 2)
        #expect(group.sources[1].variantLabel == "从零开始的异世界生活（第 1 季）")
    }

    @Test("空列表分不出组")
    func groupingEmptyList() {
        #expect(PlayableSource.grouped([]).isEmpty)
    }

    @Test("每条规则只有一个条目时，分组不改变任何东西")
    func groupingSingletonsIsIdentity() {
        let sources = PlayableSource.ranked([
            Self.scored(rule: "gugu3", title: "从零开始的异世界生活", path: "a"),
            Self.scored(rule: "baimao", title: "从零开始的异世界生活", path: "b", score: 2),
        ])

        let groups = PlayableSource.grouped(sources)

        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.sources.count == 1 })
        #expect(groups.flatMap(\.sources) == sources)
    }
}
