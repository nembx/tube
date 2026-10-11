import Foundation
import Testing
@testable import TubeKit

@Suite("SeededRuleLoader")
struct SeededRuleLoaderTests {

    @Test("seed catalog is non-empty and decodable")
    func catalogNonEmpty() throws {
        let loader = SeededRuleLoader()
        let catalog = try loader.loadSeedCatalog()
        #expect(catalog.count > 0)
        for entry in catalog {
            #expect(!entry.name.isEmpty)
            #expect(!entry.version.isEmpty)
        }
    }

    @Test("loadSeedRules returns active rules only")
    func skipDeprecated() throws {
        let loader = SeededRuleLoader()
        let rules = try loader.loadSeedRules()
        let catalog = try loader.loadSeedCatalog()
        #expect(rules.count == catalog.count, "active rule 数应该等于 catalog 条数")
    }

    @Test("seeding is idempotent (only happens when isPristine)")
    func seedOnlyOnce() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-seed-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalRuleStore(pluginsURL: url)
        let loader = SeededRuleLoader()

        // 第一次：应该种子
        try await loader.seedIfNeeded(into: store)
        let firstCount = try await store.load().count
        #expect(firstCount > 0)

        // 用户手动卸载所有规则
        try await store.save([])
        let afterClearCount = try await store.load().count
        #expect(afterClearCount == 0)

        // 第二次：plugins.json 已存在，不应该 re-seed
        try await loader.seedIfNeeded(into: store)
        let secondCount = try await store.load().count
        #expect(secondCount == 0, "plugins.json 已存在时不应该 re-seed")
    }

    @Test("reconcile removes deprecated official rules and adds missing seed rules")
    func reconcileAddsAndRemoves() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tube-reconcile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalRuleStore(pluginsURL: url)
        let loader = SeededRuleLoader()
        let officialID = RuleSource.tubeRuleOfficial.id

        // 模拟旧版本地：只有 LMM（已弃用）+ 一条仍有效的 AGE，缺 TvTFun 等新源
        let staleLMM = TubeRule(
            api: "6",
            type: "anime",
            name: "LMM",
            version: "2.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        let oldAGE = TubeRule(
            api: "1",
            type: "anime",
            name: "AGE",
            version: "0.1",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        try await store.save([
            .init(rule: staleLMM, sourceID: officialID, isEnabled: true),
            .init(rule: oldAGE, sourceID: officialID, isEnabled: false),
        ])

        try await loader.reconcileOfficialSeed(into: store)
        let after = try await store.load()
        let names = Set(after.map(\.rule.name))

        #expect(!names.contains("LMM"), "弃用的官方种子应被卸掉")
        #expect(names.contains("AGE"))
        #expect(names.contains("7sefun"), "种子里的新源应被装上")
        #expect(names.contains("DM84"))

        // AGE version 应被种子覆盖，但 isEnabled 保持用户关闭状态
        let age = after.first { $0.rule.name == "AGE" }
        #expect(age?.isEnabled == false)
        #expect(age?.rule.version != "0.1")

        // 自定义源规则不应被误删
        let custom = TubeRule(
            api: "1",
            type: "anime",
            name: "myPrivate",
            version: "1.0",
            muliSources: false,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://private.test/",
            searchURL: "https://private.test/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        var withCustom = try await store.load()
        withCustom.append(
            .init(rule: custom, sourceID: UUID(), isEnabled: true)
        )
        try await store.save(withCustom)
        try await loader.reconcileOfficialSeed(into: store)
        let finalNames = Set(try await store.load().map(\.rule.name))
        #expect(finalNames.contains("myPrivate"))
    }
}
