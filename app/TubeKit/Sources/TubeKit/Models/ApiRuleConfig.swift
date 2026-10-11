import Foundation

/// 规则搜索/章节解析模式：XPath HTML（默认）或 JSON API。
public enum RuleMode: String, Codable, Hashable, Sendable {
    case xpath
    case api

    public init(rawValueOrDefault value: String?) {
        switch value {
        case "api": self = .api
        default: self = .xpath
        }
    }
}

/// API 请求体类型。
public enum ApiBodyType: String, Codable, Hashable, Sendable {
    case none
    case json
    case form

    public init(rawValueOrDefault value: String?) {
        switch value {
        case "json": self = .json
        case "form": self = .form
        default: self = .none
        }
    }
}

/// 章节 API 响应格式。
public enum ApiChapterFormat: String, Codable, Hashable, Sendable {
    case nested
    case delimited

    public init(rawValueOrDefault value: String?) {
        switch value {
        case "delimited": self = .delimited
        default: self = .nested
        }
    }
}

/// 可解码为字符串的 JSON 标量（query / headers 里数字会转成字符串）。
struct StringConvertibleValue: Codable, Hashable, Sendable {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
        } else if let i = try? container.decode(Int.self) {
            value = String(i)
        } else if let d = try? container.decode(Double.self) {
            value = String(d)
        } else if let b = try? container.decode(Bool.self) {
            value = b ? "true" : "false"
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// API 请求模板。
public struct ApiRequestConfig: Codable, Hashable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var query: [String: String]
    public var bodyType: ApiBodyType
    /// JSON 字符串形式的 body 模板；`bodyType == .none` 时忽略。
    public var bodyJSON: String?

    public init(
        method: String = "GET",
        url: String = "",
        headers: [String: String] = [:],
        query: [String: String] = [:],
        bodyType: ApiBodyType = .none,
        bodyJSON: String? = nil
    ) {
        self.method = method.uppercased()
        self.url = url
        self.headers = headers
        self.query = query
        self.bodyType = bodyType
        self.bodyJSON = bodyJSON
    }

    private enum CodingKeys: String, CodingKey {
        case method, url, headers, query, bodyType, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = (try c.decodeIfPresent(String.self, forKey: .method) ?? "GET").uppercased()
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        let rawHeaders =
            try c.decodeIfPresent([String: StringConvertibleValue].self, forKey: .headers) ?? [:]
        headers = rawHeaders.mapValues(\.value)
        let rawQuery =
            try c.decodeIfPresent([String: StringConvertibleValue].self, forKey: .query) ?? [:]
        query = rawQuery.mapValues(\.value)
        bodyType = ApiBodyType(
            rawValueOrDefault: try c.decodeIfPresent(String.self, forKey: .bodyType)
        )
        if let body = try? c.decodeIfPresent(String.self, forKey: .body) {
            bodyJSON = body
        } else if c.contains(.body),
            let obj = try? c.decode([String: StringConvertibleValue].self, forKey: .body)
        {
            let dict = obj.mapValues(\.value)
            bodyJSON = String(
                data: try JSONSerialization.data(withJSONObject: dict),
                encoding: .utf8
            )
        } else {
            bodyJSON = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(method, forKey: .method)
        try c.encode(url, forKey: .url)
        if !headers.isEmpty { try c.encode(headers, forKey: .headers) }
        if !query.isEmpty { try c.encode(query, forKey: .query) }
        if bodyType != .none { try c.encode(bodyType.rawValue, forKey: .bodyType) }
        if let bodyJSON, bodyType != .none {
            if let data = bodyJSON.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data)
            {
                try c.encode(AnyEncodableJSON(obj), forKey: .body)
            } else {
                try c.encode(bodyJSON, forKey: .body)
            }
        }
    }
}

/// 搜索 API 配置（`searchMode = api`）。
public struct ApiSearchConfig: Codable, Hashable, Sendable {
    public var request: ApiRequestConfig
    public var listPath: String
    public var namePath: String
    public var sourcePath: String

    public init(
        request: ApiRequestConfig = ApiRequestConfig(),
        listPath: String = "$.data[*]",
        namePath: String = "$.name",
        sourcePath: String = "$.url"
    ) {
        self.request = request
        self.listPath = listPath
        self.namePath = namePath
        self.sourcePath = sourcePath
    }
}

/// 播放页 URL 模板（当响应里没有直接播放 URL 时用）。
public struct ApiEpisodePageConfig: Codable, Hashable, Sendable {
    public var url: String
    public var query: [String: String]

    public init(url: String = "", query: [String: String] = [:]) {
        self.url = url
        self.query = query
    }

    private enum CodingKeys: String, CodingKey {
        case url, query
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        let raw = try c.decodeIfPresent([String: StringConvertibleValue].self, forKey: .query) ?? [:]
        query = raw.mapValues(\.value)
    }
}

/// 章节 API 配置（`chapterMode = api`）。
public struct ApiChapterConfig: Codable, Hashable, Sendable {
    public var request: ApiRequestConfig
    public var format: ApiChapterFormat

    // nested
    public var roadsPath: String
    public var roadNamePath: String
    public var episodesPath: String
    public var episodeNamePath: String
    public var episodeUrlPath: String

    // delimited
    public var roadNamesPath: String
    public var roadEpisodesPath: String
    public var roadSeparator: String
    public var episodeSeparator: String
    public var fieldSeparator: String

    public var variables: [String: String]
    public var episodePage: ApiEpisodePageConfig?

    public init(
        request: ApiRequestConfig = ApiRequestConfig(),
        format: ApiChapterFormat = .nested,
        roadsPath: String = "$.data.roads[*]",
        roadNamePath: String = "$.name",
        episodesPath: String = "$.episodes[*]",
        episodeNamePath: String = "$.name",
        episodeUrlPath: String = "$.url",
        roadNamesPath: String = "",
        roadEpisodesPath: String = "",
        roadSeparator: String = "$$$",
        episodeSeparator: String = "#",
        fieldSeparator: String = "$",
        variables: [String: String] = [:],
        episodePage: ApiEpisodePageConfig? = nil
    ) {
        self.request = request
        self.format = format
        self.roadsPath = roadsPath
        self.roadNamePath = roadNamePath
        self.episodesPath = episodesPath
        self.episodeNamePath = episodeNamePath
        self.episodeUrlPath = episodeUrlPath
        self.roadNamesPath = roadNamesPath
        self.roadEpisodesPath = roadEpisodesPath
        self.roadSeparator = roadSeparator
        self.episodeSeparator = episodeSeparator
        self.fieldSeparator = fieldSeparator
        self.variables = variables
        self.episodePage = episodePage
    }

    private enum CodingKeys: String, CodingKey {
        case request, format
        case roadsPath, roadNamePath, episodesPath, episodeNamePath, episodeUrlPath
        case roadNamesPath, roadEpisodesPath, roadSeparator, episodeSeparator, fieldSeparator
        case variables, episodePage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        request = try c.decodeIfPresent(ApiRequestConfig.self, forKey: .request) ?? ApiRequestConfig()
        format = ApiChapterFormat(
            rawValueOrDefault: try c.decodeIfPresent(String.self, forKey: .format)
        )
        roadsPath = try c.decodeIfPresent(String.self, forKey: .roadsPath) ?? "$.data.roads[*]"
        roadNamePath = try c.decodeIfPresent(String.self, forKey: .roadNamePath) ?? "$.name"
        episodesPath = try c.decodeIfPresent(String.self, forKey: .episodesPath) ?? "$.episodes[*]"
        episodeNamePath =
            try c.decodeIfPresent(String.self, forKey: .episodeNamePath) ?? "$.name"
        episodeUrlPath = try c.decodeIfPresent(String.self, forKey: .episodeUrlPath) ?? "$.url"
        roadNamesPath = try c.decodeIfPresent(String.self, forKey: .roadNamesPath) ?? ""
        roadEpisodesPath = try c.decodeIfPresent(String.self, forKey: .roadEpisodesPath) ?? ""
        roadSeparator = try c.decodeIfPresent(String.self, forKey: .roadSeparator) ?? "$$$"
        episodeSeparator = try c.decodeIfPresent(String.self, forKey: .episodeSeparator) ?? "#"
        fieldSeparator = try c.decodeIfPresent(String.self, forKey: .fieldSeparator) ?? "$"
        variables = try c.decodeIfPresent([String: String].self, forKey: .variables) ?? [:]
        episodePage = try c.decodeIfPresent(ApiEpisodePageConfig.self, forKey: .episodePage)
    }
}

/// 编码任意 JSON 值（仅用于 `ApiRequestConfig.encode`）。
private struct AnyEncodableJSON: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyEncodableJSON($0) })
        case let v as [Any]:
            try container.encode(v.map { AnyEncodableJSON($0) })
        default:
            try container.encodeNil()
        }
    }
}
