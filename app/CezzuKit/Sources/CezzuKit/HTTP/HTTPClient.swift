import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 单例 HTTP 客户端，按规则注入 UA / Referer，与 `URLSession.shared.cookieStore`
/// 共享 cookie 域（同时也是 `WKHTTPCookieStore` 的存储）。
public actor HTTPClient {
    public static let shared = HTTPClient()

    private let session: URLSession
    private let cookieStore: PluginCookieStore

    public init(session: URLSession? = nil, cookieStore: PluginCookieStore = .shared) {
        self.cookieStore = cookieStore
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 30
            cfg.httpCookieStorage = HTTPCookieStorage.shared
            cfg.httpCookieAcceptPolicy = .always
            cfg.httpShouldSetCookies = true
            self.session = URLSession(configuration: cfg)
        }
    }

    /// GET，按规则注入头部。
    public func get(_ url: URL, rule: CezzuRule) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req, rule: rule)
        await applyCookies(to: &req, ruleName: rule.name, url: url)
        return try await perform(req, rule: rule)
    }

    /// POST 表单（用于 `usePost = true` 的规则）。
    public func post(
        _ url: URL,
        rule: CezzuRule,
        formBody: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyHeaders(to: &req, rule: rule)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = encodeForm(formBody).data(using: .utf8)
        await applyCookies(to: &req, ruleName: rule.name, url: url)
        return try await perform(req, rule: rule)
    }

    /// 执行已渲染的 API 规则请求（`searchMode` / `chapterMode` = api）。
    public func performPrepared(
        _ prepared: PreparedRuleRequest,
        rule: CezzuRule
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: prepared.url)
        req.httpMethod = prepared.method
        applyHeaders(to: &req, rule: rule)
        for (key, value) in prepared.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if prepared.method == "POST", let body = prepared.body {
            req.httpBody = body
            switch prepared.bodyType {
            case .json:
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            case .form:
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    req.setValue(
                        "application/x-www-form-urlencoded",
                        forHTTPHeaderField: "Content-Type"
                    )
                }
            case .none:
                break
            }
        }
        await applyCookies(to: &req, ruleName: rule.name, url: prepared.url)
        return try await perform(req, rule: rule)
    }

    // MARK: - internals

    private func applyCookies(to req: inout URLRequest, ruleName: String, url: URL) async {
        let cookies = await cookieStore.cookies(for: ruleName, matching: url)
        guard !cookies.isEmpty else { return }
        let header = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in header {
            req.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func applyHeaders(to req: inout URLRequest, rule: CezzuRule) {
        let ua = rule.userAgent.isEmpty ? RandomUA.next() : rule.userAgent
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if !rule.referer.isEmpty {
            req.setValue(rule.referer, forHTTPHeaderField: "Referer")
        }
    }

    private func encodeForm(_ body: [String: String]) -> String {
        body.map { (k, v) in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }
        .joined(separator: "&")
    }

    private func perform(
        _ req: URLRequest,
        rule: CezzuRule
    ) async throws -> (Data, HTTPURLResponse) {
        let ruleName = rule.name
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw RuleEngineError.parse(
                    message: "non-HTTP response",
                    rule: ruleName
                )
            }
            guard (200...299).contains(http.statusCode) else {
                // Cloudflare 一类的防护是直接 403 挡在门外，body 里没有任何可探测的
                // 验证码节点，`detectCaptcha` 永远等不到 HTML。规则声明了反爬时把
                // 403 升级成验证码挑战，交给已有的 WebView 流程去过。
                if http.statusCode == 403, rule.antiCrawlerConfig?.enabled == true {
                    throw RuleEngineError.captchaRequired(rule: ruleName)
                }
                throw RuleEngineError.http(status: http.statusCode, rule: ruleName)
            }
            return (data, http)
        } catch is CancellationError {
            throw RuleEngineError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw RuleEngineError.timeout(rule: ruleName)
            }
            if urlError.code == .cancelled {
                throw RuleEngineError.cancelled
            }
            throw RuleEngineError.parse(
                message: urlError.localizedDescription,
                rule: ruleName
            )
        }
    }
}
