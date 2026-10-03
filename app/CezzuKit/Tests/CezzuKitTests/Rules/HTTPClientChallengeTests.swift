import Foundation
import Testing
@testable import CezzuKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Cloudflare 一类的防护直接 403 挡在门外，body 里没有任何可探测的验证码节点，
/// `LiveRuleEngine.detectCaptcha` 永远等不到 HTML。403 必须在 HTTP 层就升级成
/// 验证码挑战，才能接上已有的 WebView 过验证流程。
///
/// 用自己的 URLProtocol 子类（不复用 `StubURLProtocol`）：那个静态 handler 是
/// 跨 suite 共享的，`.serialized` 只在 suite 内生效，蹭用会和别的 suite 抢。
@Suite("HTTPClient anti-crawler challenge", .serialized)
struct HTTPClientChallengeTests {

    private func rule(antiCrawler: Bool) -> CezzuRule {
        CezzuRule(
            api: antiCrawler ? "6" : "1",
            type: "anime",
            name: "probe",
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/s?q=@keyword",
            searchList: "//li",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a",
            antiCrawlerConfig: antiCrawler
                ? AntiCrawlerConfig(
                    enabled: true,
                    captchaType: .autoClickButton,
                    captchaImage: "",
                    captchaInput: "",
                    captchaButton: "//button"
                )
                : nil
        )
    }

    @Test("403 becomes a captcha challenge when the rule declares anti-crawler")
    func challengeOn403() async {
        let client = HTTPClient(session: .challengeStub(status: 403))
        await #expect(thrown(by: client, rule: rule(antiCrawler: true)) == .captcha)
    }

    /// 没声明反爬的规则不该被改变行为 —— 403 仍然是普通 HTTP 错误。
    @Test("403 stays an http error for rules without anti-crawler")
    func plain403WithoutAntiCrawler() async {
        let client = HTTPClient(session: .challengeStub(status: 403))
        await #expect(thrown(by: client, rule: rule(antiCrawler: false)) == .http(403))
    }

    /// 只升级 403。其他失败码照旧，别把服务端错误也塞进验证码流程。
    @Test("other error statuses are not escalated")
    func otherStatusesNotEscalated() async {
        let client = HTTPClient(session: .challengeStub(status: 500))
        await #expect(thrown(by: client, rule: rule(antiCrawler: true)) == .http(500))
    }

    /// `RuleEngineError` 不是 Equatable，压成一个可比较的结果再断言。
    private enum Outcome: Equatable {
        case captcha
        case http(Int)
        case other
        case noThrow
    }

    private func thrown(by client: HTTPClient, rule: CezzuRule) async -> Outcome {
        do {
            _ = try await client.get(URL(string: "https://example.com/s?q=x")!, rule: rule)
            return .noThrow
        } catch RuleEngineError.captchaRequired {
            return .captcha
        } catch RuleEngineError.http(let status, _) {
            return .http(status)
        } catch {
            return .other
        }
    }

    @Test("success still returns the body")
    func successPassesThrough() async throws {
        let client = HTTPClient(session: .challengeStub(status: 200, body: Data("<html/>".utf8)))
        let (data, http) = try await client.get(
            URL(string: "https://example.com/s?q=x")!, rule: rule(antiCrawler: true)
        )
        #expect(http.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "<html/>")
    }
}

extension URLSession {
    static func challengeStub(status: Int, body: Data = Data()) -> URLSession {
        ChallengeStubURLProtocol.status = status
        ChallengeStubURLProtocol.body = body
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ChallengeStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

final class ChallengeStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub")!,
            statusCode: Self.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
