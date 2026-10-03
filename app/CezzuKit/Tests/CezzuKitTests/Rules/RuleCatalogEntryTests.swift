import Foundation
import Testing
@testable import CezzuKit

@Suite("RuleCatalogEntry")
struct RuleCatalogEntryTests {

    @Test("excludingInstalled removes catalog entries by installed rule name")
    func excludingInstalledRules() {
        let catalog = [
            makeEntry(name: "AGE"),
            makeEntry(name: "LMM"),
            makeEntry(name: "AGE", sourceID: UUID()),
        ]
        let installed = [
            InstalledRule(rule: makeRule(name: "AGE"), sourceID: nil, isEnabled: true)
        ]

        let filtered = catalog.excludingInstalled(installed)

        #expect(filtered.map(\.name) == ["LMM"])
    }

    private func makeEntry(name: String, sourceID: UUID? = nil) -> RuleCatalogEntry {
        RuleCatalogEntry(
            name: name,
            version: "1.0",
            useNativePlayer: true,
            antiCrawlerEnabled: false,
            author: "",
            lastUpdate: 0,
            sourceID: sourceID
        )
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
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
    }
}
