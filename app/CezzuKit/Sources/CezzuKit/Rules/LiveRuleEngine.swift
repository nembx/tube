import Foundation

/// `RuleEngine` 的生产实现 —— 真的会发 HTTP 请求 + 跑 XPath。
public final class LiveRuleEngine: RuleEngine, Sendable {
    private let httpClient: HTTPClient
    private let documentFactory: XPathDocumentFactory

    public init(
        httpClient: HTTPClient = .shared,
        documentFactory: @escaping XPathDocumentFactory = KannaXPathHTMLDocument.factory
    ) {
        self.httpClient = httpClient
        self.documentFactory = documentFactory
    }

    // MARK: - search

    public func search(
        _ keyword: String,
        with rule: CezzuRule
    ) async throws -> [SearchResult] {
        if rule.searchMode == .api {
            return try await searchAPI(keyword, with: rule)
        }
        guard let url = rule.resolvedSearchURL(for: keyword) else {
            throw RuleEngineError.invalidURL(rule.searchURL)
        }
        let (data, _): (Data, HTTPURLResponse)
        if rule.usePost {
            (data, _) = try await httpClient.post(url, rule: rule, formBody: ["wd": keyword])
        } else {
            (data, _) = try await httpClient.get(url, rule: rule)
        }
        let html = decodeHTML(data: data)
        return try parseSearchResults(html: html, rule: rule)
    }

    private func searchAPI(
        _ keyword: String,
        with rule: CezzuRule
    ) async throws -> [SearchResult] {
        guard let config = rule.searchApiConfig else {
            throw RuleEngineError.parse(
                message: "searchMode=api 但缺少 searchApiConfig",
                rule: rule.name
            )
        }
        do {
            let prepared = try ApiRuleEngine.prepareRequest(
                config.request,
                variables: ["keyword": keyword]
            )
            let (data, _) = try await httpClient.performPrepared(prepared, rule: rule)
            return try ApiRuleEngine.parseSearch(
                data: data,
                config: config,
                ruleName: rule.name
            )
        } catch let error as RestrictedJSONPath.FormatError {
            throw RuleEngineError.parse(message: error.message, rule: rule.name)
        }
    }

    func parseSearchResults(html: String, rule: CezzuRule) throws -> [SearchResult] {
        let doc: any XPathHTMLDocument
        do {
            doc = try documentFactory(html)
        } catch {
            throw RuleEngineError.parse(
                message: "HTML parse failed: \(error)",
                rule: rule.name
            )
        }
        try detectCaptcha(doc: doc, rule: rule)
        guard let baseURL = URL(string: rule.baseURL) else {
            throw RuleEngineError.invalidURL(rule.baseURL)
        }
        let listNodes = doc.xpath(rule.searchList)
        var results: [SearchResult] = []
        for node in listNodes {
            let title = pickFirstText(node.xpath(rule.searchName))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resultNodes = node.xpath(rule.searchResult)
            guard
                let title = title, !title.isEmpty,
                let href = resultNodes.first?["href"], !href.isEmpty,
                let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }
            results.append(
                SearchResult(title: title, detailURL: resolved, ruleName: rule.name)
            )
        }
        return results
    }

    // MARK: - episodes

    public func fetchEpisodes(
        detailURL: URL,
        with rule: CezzuRule
    ) async throws -> [EpisodeRoad] {
        if rule.chapterMode == .api {
            return try await fetchEpisodesAPI(detailURL: detailURL, with: rule)
        }
        let (data, _) = try await httpClient.get(detailURL, rule: rule)
        let html = decodeHTML(data: data)
        return try parseEpisodes(html: html, rule: rule, baseURL: detailURL)
    }

    private func fetchEpisodesAPI(
        detailURL: URL,
        with rule: CezzuRule
    ) async throws -> [EpisodeRoad] {
        guard let config = rule.chapterApiConfig else {
            throw RuleEngineError.parse(
                message: "chapterMode=api 但缺少 chapterApiConfig",
                rule: rule.name
            )
        }
        let source = ApiRuleEngine.source(from: detailURL)
        do {
            let prepared = try ApiRuleEngine.prepareRequest(
                config.request,
                variables: ["source": source]
            )
            let (data, _) = try await httpClient.performPrepared(prepared, rule: rule)
            return try ApiRuleEngine.parseChapters(
                data: data,
                config: config,
                source: source,
                baseURL: rule.baseURL
            )
        } catch let error as RestrictedJSONPath.FormatError {
            throw RuleEngineError.parse(message: error.message, rule: rule.name)
        }
    }

    func parseEpisodes(
        html: String,
        rule: CezzuRule,
        baseURL: URL
    ) throws -> [EpisodeRoad] {
        let doc: any XPathHTMLDocument
        do {
            doc = try documentFactory(html)
        } catch {
            throw RuleEngineError.parse(
                message: "HTML parse failed: \(error)",
                rule: rule.name
            )
        }
        let resolveBase = URL(string: rule.baseURL) ?? baseURL
        let roadNodes = doc.xpath(rule.chapterRoads)
        var roads: [EpisodeRoad] = []
        for (roadIdx, roadNode) in roadNodes.enumerated() {
            let chapterNodes = roadNode.xpath(rule.chapterResult)
            var episodes: [Episode] = []
            for (epIdx, chapter) in chapterNodes.enumerated() {
                let title =
                    chapter.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "第 \(epIdx + 1) 集"
                guard
                    let href = chapter["href"], !href.isEmpty,
                    let resolved = URL(string: href, relativeTo: resolveBase)?.absoluteURL
                else { continue }
                episodes.append(Episode(title: title, url: resolved, index: epIdx))
            }
            if !episodes.isEmpty {
                roads.append(
                    EpisodeRoad(
                        index: roadIdx,
                        label: "线路 \(roadIdx + 1)",
                        episodes: episodes
                    )
                )
            }
        }
        return roads
    }

    // MARK: - anti-crawler detection

    /// 根据规则的 `antiCrawlerConfig` XPath 探测当前页面是否是验证码页。
    /// 命中即抛 `.captchaRequired`，由上层决定是否弹验证码 UI。
    func detectCaptcha(doc: any XPathHTMLDocument, rule: CezzuRule) throws {
        guard let cfg = rule.antiCrawlerConfig, cfg.enabled else { return }
        let probes = [cfg.captchaImage, cfg.captchaButton].filter { !$0.isEmpty }
        guard !probes.isEmpty else { return }
        for xpath in probes where !doc.xpath(xpath).isEmpty {
            throw RuleEngineError.captchaRequired(rule: rule.name)
        }
    }

    // MARK: - helpers

    /// 从 XPath 结果取第一条非空文本。处理末尾 `/text()` 的情况。
    private func pickFirstText(_ nodes: [XPathHTMLNode]) -> String? {
        for n in nodes {
            if let t = n.text, !t.isEmpty { return t }
        }
        return nil
    }

    /// 把字节解码成 HTML 字符串。优先 UTF-8，回退 GB18030 / Latin1。
    private func decodeHTML(data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .init(rawValue: 0x80000632)) { return s }  // GB18030
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return ""
    }
}
