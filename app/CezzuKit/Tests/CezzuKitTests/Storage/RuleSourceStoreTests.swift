import Testing
@testable import CezzuKit

@Suite("RuleSourceStore")
@MainActor
struct RuleSourceStoreTests {

    @Test("ensureSeedSources seeds built-in monorepo URLs")
    func ensureSeedsBuiltInSources() {
        var inserted: [RuleSource] = []

        RuleSourceStore.reconcileSeedSources(existing: []) { source in
            inserted.append(source)
        }

        #expect(inserted.count == 2)
        #expect(inserted[0].id == RuleSource.cezzuRuleOfficial.id)
        #expect(inserted[0].indexURL.absoluteString == "https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/index.json")
        #expect(inserted[0].ruleBaseURL.absoluteString == "https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/rules/")
        #expect(inserted[1].id == RuleSource.cezzuRuleGhfast.id)
        #expect(inserted[1].indexURL.absoluteString == "https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/index.json")
        #expect(inserted[1].isEnabled == false)
    }

    @Test("ensureSeedSources migrates old built-in URLs and preserves enabled state")
    func ensureMigratesOldBuiltInSources() throws {
        let record = RuleSourceRecord(
            id: RuleSource.cezzuRuleOfficial.id,
            name: "Cezzu Rule 官方",
            indexURLString: "https://raw.githubusercontent.com/bent2685/cezzu-rule/main/index.json",
            ruleBaseURLString: "https://raw.githubusercontent.com/bent2685/cezzu-rule/main/rules/",
            mirrorPrefix: nil,
            isEnabled: false,
            isBuiltIn: true
        )
        var inserted: [RuleSource] = []

        RuleSourceStore.reconcileSeedSources(existing: [record]) { source in
            inserted.append(source)
        }

        #expect(record.indexURLString == RuleSource.cezzuRuleOfficial.indexURL.absoluteString)
        #expect(record.ruleBaseURLString == RuleSource.cezzuRuleOfficial.ruleBaseURL.absoluteString)
        #expect(record.isEnabled == false)
        #expect(inserted.map(\.id) == [RuleSource.cezzuRuleGhfast.id])
    }
}
