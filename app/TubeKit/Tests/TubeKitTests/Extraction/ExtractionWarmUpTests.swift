import Testing
import WebKit
@testable import TubeKit

@Suite("ExtractionWarmUp", .serialized)
@MainActor
struct ExtractionWarmUpTests {

    @Test("the compiled rule list is produced once and reused")
    func ruleListIsCached() async {
        let first = await ExtractionWarmUp.adBlockRuleList()
        let second = await ExtractionWarmUp.adBlockRuleList()

        // 编译一次要落盘，起播路径上白等；第二次必须是同一个对象而不是重编一遍。
        if let first {
            #expect(second === first)
        } else {
            #expect(second == nil)
        }
    }

    @Test("concurrent callers share one compilation")
    func concurrentCallersShareOneCompilation() async {
        async let a = ExtractionWarmUp.adBlockRuleList()
        async let b = ExtractionWarmUp.adBlockRuleList()
        let (first, second) = await (a, b)

        if let first {
            #expect(second === first)
        } else {
            #expect(second == nil)
        }
    }

    @Test("prewarming twice is harmless")
    func prewarmIsIdempotent() async {
        ExtractionWarmUp.prewarm()
        ExtractionWarmUp.prewarm()

        let ruleList = await ExtractionWarmUp.adBlockRuleList()
        let again = await ExtractionWarmUp.adBlockRuleList()
        if let ruleList {
            #expect(again === ruleList)
        } else {
            #expect(again == nil)
        }
    }
}
