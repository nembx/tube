import Foundation

/// 已渲染的 API 请求。
public struct PreparedRuleRequest: Hashable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var bodyType: ApiBodyType
    public var body: Data?

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        bodyType: ApiBodyType = .none,
        body: Data? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.bodyType = bodyType
        self.body = body
    }
}

/// JSON API 规则解析（对齐 Kazumi `ApiRuleStrategy`）。
public enum ApiRuleEngine: Sendable {
    public static let sourceURLScheme = "cezzu-rule"
    public static let sourceURLHost = "source"

    // MARK: - source ↔ detailURL

    /// 把 API 搜索得到的 source（可能是 URL 或 opaque id）编码成 `SearchResult.detailURL`。
    public static func detailURL(forSource source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            return url
        }
        var components = URLComponents()
        components.scheme = sourceURLScheme
        components.host = sourceURLHost
        let encoded =
            trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        components.percentEncodedPath = "/\(encoded)"
        return components.url
    }

    /// 从 `detailURL` 还原 API `@source` 变量。
    public static func source(from detailURL: URL) -> String {
        if detailURL.scheme == sourceURLScheme, detailURL.host == sourceURLHost {
            let path = detailURL.path
            let raw = path.hasPrefix("/") ? String(path.dropFirst()) : path
            return raw.removingPercentEncoding ?? raw
        }
        return detailURL.absoluteString
    }

    // MARK: - request

    public static func prepareRequest(
        _ config: ApiRequestConfig,
        variables: [String: String]
    ) throws -> PreparedRuleRequest {
        let method = config.method.uppercased()
        guard method == "GET" || method == "POST" else {
            throw RestrictedJSONPath.FormatError("仅支持 GET/POST，当前为 \(method)")
        }
        let urlTemplate = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlTemplate.isEmpty else {
            throw RestrictedJSONPath.FormatError("API 请求 URL 不能为空")
        }
        let renderedURL = try renderTemplate(urlTemplate, variables: variables, encode: true)
        guard var components = URLComponents(string: renderedURL),
            components.scheme != nil,
            components.host != nil
        else {
            throw RestrictedJSONPath.FormatError("API 请求 URL 无效: \(renderedURL)")
        }

        let renderedQuery = try renderMap(config.query, variables: variables)
        if !renderedQuery.isEmpty {
            var items = components.queryItems ?? []
            items.append(
                contentsOf: renderedQuery.keys.sorted().map {
                    URLQueryItem(name: $0, value: renderedQuery[$0])
                }
            )
            components.queryItems = items
        }
        guard let url = components.url else {
            throw RestrictedJSONPath.FormatError("API 请求 URL 无效: \(renderedURL)")
        }

        let headers = try renderMap(config.headers, variables: variables)
        var bodyData: Data?
        if method == "POST", config.bodyType != .none {
            bodyData = try renderBody(config: config, variables: variables)
        }

        return PreparedRuleRequest(
            method: method,
            url: url,
            headers: headers,
            bodyType: config.bodyType,
            body: bodyData
        )
    }

    // MARK: - search

    public static func parseSearch(
        data: Data,
        config: ApiSearchConfig,
        ruleName: String
    ) throws -> [SearchResult] {
        try validateSearchConfig(config)
        let document = try decodeJSON(data)
        let nodes = try RestrictedJSONPath.read(document, expression: config.listPath)
        var results: [SearchResult] = []
        for node in nodes {
            let name = stringValue(try RestrictedJSONPath.readFirst(node, expression: config.namePath))
            let source = stringValue(
                try RestrictedJSONPath.readFirst(node, expression: config.sourcePath)
            )
            guard !name.isEmpty, !source.isEmpty,
                let detailURL = detailURL(forSource: source)
            else { continue }
            results.append(
                SearchResult(title: name, detailURL: detailURL, ruleName: ruleName)
            )
        }
        return results
    }

    public static func validateSearchConfig(_ config: ApiSearchConfig) throws {
        try RestrictedJSONPath.validate(config.listPath)
        try RestrictedJSONPath.validate(config.namePath)
        try RestrictedJSONPath.validate(config.sourcePath)
    }

    // MARK: - chapters

    public static func parseChapters(
        data: Data,
        config: ApiChapterConfig,
        source: String,
        baseURL: String
    ) throws -> [EpisodeRoad] {
        try validateChapterConfig(config)
        let document = try decodeJSON(data)
        var rootVariables: [String: String] = ["source": source]
        for (key, path) in config.variables {
            guard let value = try RestrictedJSONPath.readFirst(document, expression: path) else {
                throw RestrictedJSONPath.FormatError(
                    "章节响应变量 \(key) 未匹配到值: \(path)"
                )
            }
            rootVariables[key] = stringValue(value)
        }

        switch config.format {
        case .delimited:
            return try parseDelimited(
                document: document,
                config: config,
                rootVariables: rootVariables,
                baseURL: baseURL
            )
        case .nested:
            return try parseNested(
                document: document,
                config: config,
                rootVariables: rootVariables,
                baseURL: baseURL
            )
        }
    }

    public static func validateChapterConfig(_ config: ApiChapterConfig) throws {
        for path in config.variables.values {
            try RestrictedJSONPath.validate(path)
        }
        if config.format == .delimited {
            try RestrictedJSONPath.validate(config.roadNamesPath)
            try RestrictedJSONPath.validate(config.roadEpisodesPath)
            if config.roadSeparator.isEmpty || config.episodeSeparator.isEmpty
                || config.fieldSeparator.isEmpty
            {
                throw RestrictedJSONPath.FormatError("章节分隔符不能为空")
            }
            return
        }

        if !config.roadsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try RestrictedJSONPath.validate(config.roadsPath)
        }
        if !config.roadNamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try RestrictedJSONPath.validate(config.roadNamePath)
        }
        try RestrictedJSONPath.validate(config.episodesPath)
        try RestrictedJSONPath.validate(config.episodeNamePath)
        if !config.episodeUrlPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try RestrictedJSONPath.validate(config.episodeUrlPath)
        } else if config.episodePage == nil {
            throw RestrictedJSONPath.FormatError("必须配置播放入口地址路径或播放页地址模板")
        }
        if let page = config.episodePage,
            page.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw RestrictedJSONPath.FormatError("播放页地址模板不能为空")
        }
    }

    // MARK: - nested / delimited

    private static func parseNested(
        document: Any,
        config: ApiChapterConfig,
        rootVariables: [String: String],
        baseURL: String
    ) throws -> [EpisodeRoad] {
        let hasRoads = !config.roadsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let roadNodes: [Any] =
            hasRoads
            ? try RestrictedJSONPath.read(document, expression: config.roadsPath)
            : [document]

        var roads: [EpisodeRoad] = []
        for (roadIndex, roadNode) in roadNodes.enumerated() {
            let roadName: String
            if hasRoads,
                !config.roadNamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                roadName = stringValue(
                    try RestrictedJSONPath.readFirst(roadNode, expression: config.roadNamePath)
                )
            } else {
                roadName = ""
            }

            let episodeNodes = try RestrictedJSONPath.read(
                roadNode,
                expression: config.episodesPath
            )
            var episodes: [Episode] = []
            for (episodeIndex, episodeNode) in episodeNodes.enumerated() {
                let episodeName = stringValue(
                    try RestrictedJSONPath.readFirst(
                        episodeNode,
                        expression: config.episodeNamePath
                    )
                )
                let rawURL: String
                if config.episodeUrlPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rawURL = ""
                } else {
                    rawURL = stringValue(
                        try RestrictedJSONPath.readFirst(
                            episodeNode,
                            expression: config.episodeUrlPath
                        )
                    )
                }
                guard
                    let pageURL = try resolveEpisodeURL(
                        config: config,
                        rootVariables: rootVariables,
                        rawURL: rawURL,
                        roadIndex: roadIndex,
                        episodeIndex: episodeIndex,
                        baseURL: baseURL
                    )
                else { continue }
                let title = episodeName.isEmpty ? "第\(episodeIndex + 1)集" : episodeName
                episodes.append(Episode(title: title, url: pageURL, index: episodeIndex))
            }
            guard !episodes.isEmpty else { continue }
            let label =
                roadName.isEmpty
                ? "播放线路\(roads.count + 1)"
                : roadName
            roads.append(EpisodeRoad(index: roadIndex, label: label, episodes: episodes))
        }
        return roads
    }

    private static func parseDelimited(
        document: Any,
        config: ApiChapterConfig,
        rootVariables: [String: String],
        baseURL: String
    ) throws -> [EpisodeRoad] {
        let namesValue = stringValue(
            try RestrictedJSONPath.readFirst(document, expression: config.roadNamesPath)
        )
        let episodesValue = stringValue(
            try RestrictedJSONPath.readFirst(document, expression: config.roadEpisodesPath)
        )
        guard !episodesValue.isEmpty else { return [] }

        let roadNames = namesValue.components(separatedBy: config.roadSeparator)
        let roadGroups = episodesValue.components(separatedBy: config.roadSeparator)
        var roads: [EpisodeRoad] = []

        for (roadIndex, group) in roadGroups.enumerated() {
            var episodes: [Episode] = []
            let entries = group.components(separatedBy: config.episodeSeparator)
            for (episodeIndex, entryRaw) in entries.enumerated() {
                let entry = entryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !entry.isEmpty else { continue }
                guard let sepRange = entry.range(of: config.fieldSeparator) else { continue }
                let name = String(entry[..<sepRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rawURL = String(entry[sepRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    let pageURL = try resolveEpisodeURL(
                        config: config,
                        rootVariables: rootVariables,
                        rawURL: rawURL,
                        roadIndex: roadIndex,
                        episodeIndex: episodeIndex,
                        baseURL: baseURL
                    )
                else { continue }
                let title = name.isEmpty ? "第\(episodeIndex + 1)集" : name
                episodes.append(Episode(title: title, url: pageURL, index: episodeIndex))
            }
            guard !episodes.isEmpty else { continue }
            let configuredName =
                roadIndex < roadNames.count
                ? roadNames[roadIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let label =
                configuredName.isEmpty
                ? "播放线路\(roads.count + 1)"
                : configuredName
            roads.append(EpisodeRoad(index: roadIndex, label: label, episodes: episodes))
        }
        return roads
    }

    private static func resolveEpisodeURL(
        config: ApiChapterConfig,
        rootVariables: [String: String],
        rawURL: String,
        roadIndex: Int,
        episodeIndex: Int,
        baseURL: String
    ) throws -> URL? {
        guard let page = config.episodePage else {
            return normalizeEpisodeURL(baseURL: baseURL, raw: rawURL)
        }
        let pageURLTemplate = page.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pageURLTemplate.isEmpty else {
            throw RestrictedJSONPath.FormatError("播放页地址模板不能为空")
        }
        var variables = rootVariables
        variables["episodeUrl"] = rawURL
        variables["roadIndex"] = String(roadIndex)
        variables["roadNumber"] = String(roadIndex + 1)
        variables["episodeIndex"] = String(episodeIndex)
        variables["episodeNumber"] = String(episodeIndex + 1)

        let path = try renderTemplate(pageURLTemplate, variables: variables, encode: true)
        guard var components = URLComponents(string: path) else {
            throw RestrictedJSONPath.FormatError("剧集页面 URL 无效: \(path)")
        }
        let renderedQuery = try renderMap(page.query, variables: variables)
        if !renderedQuery.isEmpty {
            var items = components.queryItems ?? []
            // replace existing keys
            let existingNames = Set(renderedQuery.keys)
            items.removeAll { existingNames.contains($0.name) }
            items.append(
                contentsOf: renderedQuery.keys.sorted().map {
                    URLQueryItem(name: $0, value: renderedQuery[$0])
                }
            )
            components.queryItems = items
        }
        guard let absolute = components.url?.absoluteString else {
            throw RestrictedJSONPath.FormatError("剧集页面 URL 无效: \(path)")
        }
        return normalizeEpisodeURL(baseURL: baseURL, raw: absolute)
    }

    private static func normalizeEpisodeURL(baseURL: String, raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        guard let base = URL(string: baseURL) else { return URL(string: trimmed) }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // MARK: - templates

    private static func renderMap(
        _ input: [String: String],
        variables: [String: String]
    ) throws -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in input {
            let rk = try renderTemplate(key, variables: variables, encode: false)
            let rv = try renderTemplate(value, variables: variables, encode: false)
            out[rk] = rv
        }
        return out
    }

    private static func renderBody(
        config: ApiRequestConfig,
        variables: [String: String]
    ) throws -> Data? {
        guard let bodyJSON = config.bodyJSON else { return nil }
        // body may be a JSON object template with @vars as string values
        let rendered = try renderTemplate(bodyJSON, variables: variables, encode: false)
        switch config.bodyType {
        case .json:
            return rendered.data(using: .utf8)
        case .form:
            // expect {"k":"v"} and encode as form
            guard let data = rendered.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return rendered.data(using: .utf8)
            }
            let pairs = obj.map { key, value -> String in
                let ek =
                    key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let vs = stringValue(value)
                let ev =
                    vs.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? vs
                return "\(ek)=\(ev)"
            }
            return pairs.joined(separator: "&").data(using: .utf8)
        case .none:
            return nil
        }
    }

    /// 替换模板中的 `@name` 占位符。`encode` 时对替换值做 URL encode（用于 URL path）。
    public static func renderTemplate(
        _ template: String,
        variables: [String: String],
        encode: Bool
    ) throws -> String {
        // (?<![A-Za-z0-9_])@([A-Za-z_][A-Za-z0-9_]*)
        let pattern = #"(?<![A-Za-z0-9_])@([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return template
        }
        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var result = template
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                let nameRange = Range(match.range(at: 1), in: result),
                let fullRange = Range(match.range(at: 0), in: result)
            else { continue }
            let name = String(result[nameRange])
            guard let value = variables[name] else {
                throw RestrictedJSONPath.FormatError("缺少模板变量 @\(name)")
            }
            let replacement =
                encode
                ? (value.addingPercentEncoding(withAllowedCharacters: .cezzuURLComponentAllowed)
                    ?? value)
                : value
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    // MARK: - helpers

    private static func decodeJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw RestrictedJSONPath.FormatError(
                "API 响应不是有效 JSON: \(error.localizedDescription)"
            )
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let n = value as? NSNumber {
            // Avoid "1" vs true ambiguity — use stringValue
            return n.stringValue
        }
        return String(describing: value)
    }
}

extension CharacterSet {
    /// 对齐 `Uri.encodeComponent`：只放行 unreserved 字符。
    fileprivate static let cezzuURLComponentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
