import Testing
@testable import TubeKit

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
        #expect(inserted[0].id == RuleSource.tubeRuleOfficial.id)
        #expect(inserted[0].indexURL.absoluteString == "https://raw.githubusercontent.com/nembx/tube/main/tube-rule/index.json")
        #expect(inserted[0].ruleBaseURL.absoluteString == "https://raw.githubusercontent.com/nembx/tube/main/tube-rule/rules/")
        #expect(inserted[1].id == RuleSource.tubeRuleGhfast.id)
        #expect(inserted[1].indexURL.absoluteString == "https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/tube-rule/index.json")
        #expect(inserted[1].isEnabled == false)
    }

    @Test("ensureSeedSources migrates old built-in URLs and preserves enabled state")
    func ensureMigratesOldBuiltInSources() throws {
        let record = RuleSourceRecord(
            id: RuleSource.tubeRuleOfficial.id,
            name: "Tube 默认规则",
            indexURLString: "https://raw.githubusercontent.com/bent2685/tube-rule/main/index.json",
            ruleBaseURLString: "https://raw.githubusercontent.com/bent2685/tube-rule/main/rules/",
            mirrorPrefix: nil,
            isEnabled: false,
            isBuiltIn: true
        )
        var inserted: [RuleSource] = []

        RuleSourceStore.reconcileSeedSources(existing: [record]) { source in
            inserted.append(source)
        }

        #expect(record.indexURLString == RuleSource.tubeRuleOfficial.indexURL.absoluteString)
        #expect(record.ruleBaseURLString == RuleSource.tubeRuleOfficial.ruleBaseURL.absoluteString)
        #expect(record.isEnabled == false)
        #expect(inserted.map(\.id) == [RuleSource.tubeRuleGhfast.id])
    }
}
