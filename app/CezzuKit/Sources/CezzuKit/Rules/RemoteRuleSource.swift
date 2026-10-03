import Foundation

/// 远端规则源的拉取层 —— 同时负责 catalog 抓取与单条规则下载。
public actor RemoteRuleSource {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.httpCookieStorage = HTTPCookieStorage.shared
            self.session = URLSession(configuration: cfg)
        }
    }

    /// 拉取一条规则源的 catalog。返回的条目带上 `sourceID` 标记。
    public func fetchIndex(source: RuleSource) async throws -> [RuleCatalogEntry] {
        let (data, response) = try await session.data(from: source.indexURL)
        guard let http = response as? HTTPURLResponse else {
            throw RuleEngineError.parse(message: "non-HTTP response", rule: source.name)
        }
        guard (200...299).contains(http.statusCode) else {
            throw RuleEngineError.http(status: http.statusCode, rule: source.name)
        }
        var entries = try JSONDecoder().decode([RuleCatalogEntry].self, from: data)
        for i in entries.indices { entries[i].sourceID = source.id }
        return entries
    }

    /// 拉取并解码单条规则。失败抛 `RuleEngineError`。
    public func fetchRule(name: String, source: RuleSource) async throws -> CezzuRule {
        guard let url = source.ruleURL(for: name) else {
            throw RuleEngineError.invalidURL("\(source.ruleBaseURL)/\(name).json")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw RuleEngineError.parse(message: "non-HTTP response", rule: name)
        }
        guard (200...299).contains(http.statusCode) else {
            throw RuleEngineError.http(status: http.statusCode, rule: name)
        }
        do {
            return try JSONDecoder().decode(CezzuRule.self, from: data)
        } catch {
            throw RuleEngineError.parse(
                message: "decode failed: \(error)",
                rule: name
            )
        }
    }

    /// 自定义源添加前的校验：URL 合法 + index.json 解码 + 至少一条 entry。
    public func validateCustomSource(_ source: RuleSource) async throws {
        guard source.indexURL.scheme?.lowercased() == "https" else {
            throw RuleEngineError.invalidURL("URL scheme 必须是 https")
        }
        guard let host = source.indexURL.host, !host.isEmpty else {
            throw RuleEngineError.invalidURL("URL host 不能为空")
        }
        let entries = try await fetchIndex(source: source)
        if entries.isEmpty {
            throw RuleEngineError.noResults(rule: source.name)
        }
    }
}
