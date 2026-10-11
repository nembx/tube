import Foundation
import Testing

@testable import TubeKit

@Suite("RuleStore error reporting")
@MainActor
struct RuleStoreErrorReportingTests {

    @Test("404 的提示点名是规则源上没有这条规则")
    func notFoundMessage() {
        let error = RuleEngineError.http(status: 404, rule: "AGE")
        #expect(error.userMessage.contains("404"))
        #expect(error.userMessage != error.description)
    }

    @Test("其余 HTTP 状态码原样带出")
    func otherHTTPStatusMessage() {
        #expect(RuleEngineError.http(status: 503, rule: "AGE").userMessage.contains("503"))
    }

    @Test("解码失败不会把 Swift 的 DecodingError 甩给用户")
    func parseMessageStaysUserFacing() {
        let error = RuleEngineError.parse(message: "keyNotFound(captchaType)", rule: "ezdmw")
        #expect(!error.userMessage.contains("keyNotFound"))
    }

    @Test("非 RuleEngineError 回落到 localizedDescription")
    func nonRuleEngineErrorFallsBack() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "离线"]
        )
        #expect(RuleStoreCoordinator.reason(for: error) == "离线")
    }

    @Test("失败信息带上动作名，用户知道是哪一步挂了")
    func failureMessageNamesTheAction() {
        let message = RuleStoreCoordinator.failureMessage(
            action: "安装 AGE",
            error: RuleEngineError.http(status: 404, rule: "AGE")
        )
        #expect(message.hasPrefix("安装 AGE失败："))
        #expect(message.contains("404"))
    }
}
