import Foundation
import Testing
@testable import CezzuKit

@Suite("LocalRuleStore")
struct LocalRuleStoreTests {

    private func tempStore() -> (LocalRuleStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cezzu-test-\(UUID().uuidString).json")
        return (LocalRuleStore(pluginsURL: url), url)
    }

    private func sampleRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "1",
            type: "anime",
            name: name,
            version: "1.0",
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
    }

    @Test("install + load + survive restart")
    func installAndLoad() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.install(rule: sampleRule(name: "foo"), sourceID: nil)
        try await store.install(rule: sampleRule(name: "bar"), sourceID: nil)

        // 模拟重启 —— 用同 URL 新建 store
        let restarted = LocalRuleStore(pluginsURL: url)
        let loaded = try await restarted.load()
        #expect(loaded.count == 2)
        #expect(loaded.contains(where: { $0.rule.name == "foo" }))
        #expect(loaded.contains(where: { $0.rule.name == "bar" }))
    }

    @Test("uninstall removes one rule")
    func uninstall() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.install(rule: sampleRule(name: "foo"), sourceID: nil)
        try await store.install(rule: sampleRule(name: "bar"), sourceID: nil)
        try await store.uninstall(name: "foo")

        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].rule.name == "bar")
    }

    @Test("setEnabled toggles isEnabled")
    func setEnabled() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.install(rule: sampleRule(name: "foo"), sourceID: nil)
        try await store.setEnabled(name: "foo", enabled: false)
        let loaded = try await store.load()
        #expect(loaded[0].isEnabled == false)
    }

    @Test("isPristine flips after first save")
    func isPristine() async throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let pristine = await store.isPristine
        #expect(pristine == true)

        try await store.install(rule: sampleRule(name: "foo"), sourceID: nil)
        let pristine2 = await store.isPristine
        #expect(pristine2 == false)
    }
}
