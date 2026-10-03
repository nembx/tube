import Foundation
import Testing

@testable import CezzuKit

@Suite("SearchCoordinator")
struct SearchCoordinatorTests {

    /// 按规则名配置响应延迟的假引擎。
    struct DelayedRuleEngine: RuleEngine {
        let delaysByRuleName: [String: Duration]

        func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult] {
            if let delay = delaysByRuleName[rule.name] {
                try await Task.sleep(for: delay)
            }
            return [
                SearchResult(
                    title: "\(rule.name)-\(keyword)",
                    detailURL: URL(string: "https://\(rule.name).example/\(keyword.count)")!,
                    ruleName: rule.name
                )
            ]
        }

        func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad] { [] }
    }

    /// 回归：整轮上限曾经硬编码在每个调用点上（4 秒），慢站回得晚一点结果就被静默丢弃。
    /// 现在上限收在 coordinator 里，慢站只要在上限内回话，结果就必须送达。
    @Test("results that arrive after the old 4s cutoff are still delivered")
    func slowRuleStillDelivers() async {
        let engine = DelayedRuleEngine(delaysByRuleName: ["slow": .milliseconds(400)])
        let coordinator = SearchCoordinator(
            engine: engine,
            perRuleTimeoutSeconds: 2,
            overallTimeoutSeconds: 3
        )

        var received: [String: [SearchResult]] = [:]
        for await update in coordinator.searchAll(
            keywords: ["k"],
            rules: [makeRule(name: "fast"), makeRule(name: "slow")]
        ) {
            if case .ruleResults(let name, let results) = update {
                received[name] = results
            }
        }

        #expect(received["fast"]?.count == 1)
        #expect(received["slow"]?.count == 1)
    }

    /// 单条规则超时只淘汰它自己，不能拖累同轮的其它规则。
    @Test("a rule that exceeds the per-rule timeout fails alone")
    func perRuleTimeoutIsolatesTheSlowRule() async {
        let engine = DelayedRuleEngine(delaysByRuleName: ["dead": .seconds(5)])
        let coordinator = SearchCoordinator(
            engine: engine,
            perRuleTimeoutSeconds: 0.3,
            overallTimeoutSeconds: 3
        )

        var results: [String: [SearchResult]] = [:]
        var failed: Set<String> = []
        for await update in coordinator.searchAll(
            keywords: ["k"],
            rules: [makeRule(name: "alive"), makeRule(name: "dead")]
        ) {
            switch update {
            case .ruleResults(let name, let value): results[name] = value
            case .ruleFailed(let name, _): failed.insert(name)
            default: break
            }
        }

        #expect(results["alive"]?.count == 1)
        #expect(failed.contains("dead"))
        #expect(results["dead"] == nil)
    }

    /// 整轮上限必须真的收口，否则详情页的 spinner 会一直转。
    @Test("the overall timeout finishes the stream instead of hanging")
    func overallTimeoutFinishesStream() async {
        let engine = DelayedRuleEngine(delaysByRuleName: ["slow": .seconds(10)])
        let coordinator = SearchCoordinator(
            engine: engine,
            perRuleTimeoutSeconds: 30,
            overallTimeoutSeconds: 0.3
        )

        let started = ContinuousClock.now
        var resultCount = 0
        for await update in coordinator.searchAll(keywords: ["k"], rules: [makeRule(name: "slow")]) {
            if case .ruleResults = update { resultCount += 1 }
        }
        let elapsed = ContinuousClock.now - started

        #expect(resultCount == 0)
        // per-rule 上限是 30s，能在 2s 内收口就说明是整轮上限掐断的
        #expect(elapsed < .seconds(2))
    }

    /// 每个关键词都会对每条规则各发一次，调用方靠这个拿到别名命中的结果。
    @Test("every keyword is dispatched to every rule")
    func everyKeywordHitsEveryRule() async {
        let coordinator = SearchCoordinator(
            engine: DelayedRuleEngine(delaysByRuleName: [:]),
            perRuleTimeoutSeconds: 2,
            overallTimeoutSeconds: 3
        )

        var titles: Set<String> = []
        for await update in coordinator.searchAll(
            keywords: ["ab", "cde"],
            rules: [makeRule(name: "R1"), makeRule(name: "R2")]
        ) {
            if case .ruleResults(_, let results) = update {
                titles.formUnion(results.map(\.title))
            }
        }

        #expect(titles == ["R1-ab", "R1-cde", "R2-ab", "R2-cde"])
    }

    private func makeRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "1",
            type: "anime",
            name: name,
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//div",
            searchName: "//a/text()",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
    }
}
