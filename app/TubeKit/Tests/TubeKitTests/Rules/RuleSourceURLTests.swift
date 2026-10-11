import Foundation
import Testing

@testable import TubeKit

@Suite("RuleSource ruleURL")
struct RuleSourceURLTests {

    private func source(base: String) -> RuleSource {
        RuleSource(
            name: "t",
            indexURL: URL(string: "https://example.com/index.json")!,
            ruleBaseURL: URL(string: base)!,
            isEnabled: true,
            isBuiltIn: false
        )
    }

    @Test("base 以 / 结尾时拼在末尾")
    func trailingSlashBase() {
        let s = source(base: "https://example.com/repo/rules/")
        #expect(s.ruleURL(for: "AGE")?.absoluteString == "https://example.com/repo/rules/AGE.json")
    }

    @Test("base 没有结尾 / 时不能吃掉最后一段路径")
    func missingTrailingSlashKeepsLastComponent() {
        let s = source(base: "https://example.com/repo/rules")
        #expect(s.ruleURL(for: "AGE")?.absoluteString == "https://example.com/repo/rules/AGE.json")
    }

    @Test("镜像前缀式 base 原样保留")
    func mirrorPrefixedBase() {
        let s = source(base: "https://ghfast.top/https://raw.githubusercontent.com/o/r/main/rules/")
        #expect(
            s.ruleURL(for: "AGE")?.absoluteString
                == "https://ghfast.top/https://raw.githubusercontent.com/o/r/main/rules/AGE.json"
        )
    }

    @Test("规则名里的空格被转义而不是产生 nil")
    func ruleNameNeedingEscaping() {
        let s = source(base: "https://example.com/rules/")
        #expect(s.ruleURL(for: "my rule") != nil)
    }
}
