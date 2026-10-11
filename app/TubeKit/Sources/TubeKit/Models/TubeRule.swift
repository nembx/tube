import Foundation

/// Cezzu 的 JSON 规则模型 —— cezzu-rule 格式的 Swift 对应物。
///
/// 对应的 schema 文档见 `cezzu-rule/docs/rule-format.md`。
/// 注意：
///   - `api` 与 `version` 都是 `String`（不是 Int）
///   - 历史拼写 `muliSources`（少一个 `t`）**保留原样**，是 cezzu-rule 格式的一部分
///   - 可选字段（`usePost` / `searchMode` / `searchApiConfig` 等）都有默认值
public struct TubeRule: Codable, Hashable, Sendable, Identifiable {

    // 必填字段
    public var api: String
    public var type: String
    public var name: String
    public var version: String
    public var muliSources: Bool
    public var useWebview: Bool
    public var useNativePlayer: Bool
    public var userAgent: String
    public var baseURL: String
    public var searchURL: String
    public var searchList: String
    public var searchName: String
    public var searchResult: String
    public var chapterRoads: String
    public var chapterResult: String

    // 可选字段
    public var usePost: Bool
    public var useLegacyParser: Bool
    public var adBlocker: Bool
    public var referer: String
    public var antiCrawlerConfig: AntiCrawlerConfig?

    /// 搜索解析模式。默认 `xpath`；`api` 时走 `searchApiConfig`。
    public var searchMode: RuleMode
    /// 章节解析模式。默认 `xpath`；`api` 时走 `chapterApiConfig`。
    public var chapterMode: RuleMode
    public var searchApiConfig: ApiSearchConfig?
    public var chapterApiConfig: ApiChapterConfig?

    /// 播放页要预置的 cookie，`"k=v; k2=v2"`。**API ≥ 9**。
    /// 站点把清晰度 / 语言这类选择存在 cookie 里时用它，空串 = 不预置。
    public var cookies: String
    /// 嗅探结果的正则过滤，命名组 `v` 用来提取真实地址。**API ≥ 9**。
    /// 空串 = 全放行（既有规则行为不变）。
    public var videoURLPattern: String

    /// `Identifiable` 用 `name` 作为 id —— 规则名是全局唯一键。
    public var id: String { name }

    public init(
        api: String,
        type: String,
        name: String,
        version: String,
        muliSources: Bool,
        useWebview: Bool,
        useNativePlayer: Bool,
        userAgent: String,
        baseURL: String,
        searchURL: String,
        searchList: String,
        searchName: String,
        searchResult: String,
        chapterRoads: String,
        chapterResult: String,
        usePost: Bool = false,
        useLegacyParser: Bool = false,
        adBlocker: Bool = false,
        referer: String = "",
        antiCrawlerConfig: AntiCrawlerConfig? = nil,
        searchMode: RuleMode = .xpath,
        chapterMode: RuleMode = .xpath,
        searchApiConfig: ApiSearchConfig? = nil,
        chapterApiConfig: ApiChapterConfig? = nil,
        cookies: String = "",
        videoURLPattern: String = ""
    ) {
        self.api = api
        self.type = type
        self.name = name
        self.version = version
        self.muliSources = muliSources
        self.useWebview = useWebview
        self.useNativePlayer = useNativePlayer
        self.userAgent = userAgent
        self.baseURL = baseURL
        self.searchURL = searchURL
        self.searchList = searchList
        self.searchName = searchName
        self.searchResult = searchResult
        self.chapterRoads = chapterRoads
        self.chapterResult = chapterResult
        self.usePost = usePost
        self.useLegacyParser = useLegacyParser
        self.adBlocker = adBlocker
        self.referer = referer
        self.antiCrawlerConfig = antiCrawlerConfig
        self.searchMode = searchMode
        self.chapterMode = chapterMode
        self.searchApiConfig = searchApiConfig
        self.chapterApiConfig = chapterApiConfig
        self.cookies = cookies
        self.videoURLPattern = videoURLPattern
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case api
        case type
        case name
        case version
        case muliSources    // ← 历史拼写，cezzu-rule 格式一部分
        case useWebview
        case useNativePlayer
        case userAgent
        case baseURL
        case searchURL
        case searchList
        case searchName
        case searchResult
        case chapterRoads
        case chapterResult
        case usePost
        case useLegacyParser
        case adBlocker
        case referer
        case antiCrawlerConfig
        case searchMode
        case chapterMode
        case searchApiConfig
        case chapterApiConfig
        case cookies
        case videoURLPattern
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.api = try c.decode(String.self, forKey: .api)
        self.type = try c.decode(String.self, forKey: .type)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.muliSources = try c.decode(Bool.self, forKey: .muliSources)
        self.useWebview = try c.decode(Bool.self, forKey: .useWebview)
        self.useNativePlayer = try c.decode(Bool.self, forKey: .useNativePlayer)
        self.userAgent = try c.decode(String.self, forKey: .userAgent)
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.searchURL = try c.decode(String.self, forKey: .searchURL)
        self.searchList = try c.decode(String.self, forKey: .searchList)
        self.searchName = try c.decode(String.self, forKey: .searchName)
        self.searchResult = try c.decode(String.self, forKey: .searchResult)
        self.chapterRoads = try c.decode(String.self, forKey: .chapterRoads)
        self.chapterResult = try c.decode(String.self, forKey: .chapterResult)

        // 可选字段 —— 与格式约定的默认值
        self.usePost = try c.decodeIfPresent(Bool.self, forKey: .usePost) ?? false
        self.useLegacyParser =
            try c.decodeIfPresent(Bool.self, forKey: .useLegacyParser) ?? false
        self.adBlocker = try c.decodeIfPresent(Bool.self, forKey: .adBlocker) ?? false
        self.referer = try c.decodeIfPresent(String.self, forKey: .referer) ?? ""
        self.antiCrawlerConfig =
            try c.decodeIfPresent(AntiCrawlerConfig.self, forKey: .antiCrawlerConfig)
        self.searchMode = RuleMode(
            rawValueOrDefault: try c.decodeIfPresent(String.self, forKey: .searchMode)
        )
        self.chapterMode = RuleMode(
            rawValueOrDefault: try c.decodeIfPresent(String.self, forKey: .chapterMode)
        )
        self.searchApiConfig =
            try c.decodeIfPresent(ApiSearchConfig.self, forKey: .searchApiConfig)
        self.chapterApiConfig =
            try c.decodeIfPresent(ApiChapterConfig.self, forKey: .chapterApiConfig)
        self.cookies = try c.decodeIfPresent(String.self, forKey: .cookies) ?? ""
        self.videoURLPattern =
            try c.decodeIfPresent(String.self, forKey: .videoURLPattern) ?? ""
    }

    // MARK: Convenience

    /// 把 `searchURL` 中的字面量 `@keyword` 替换为 URL-encoded 关键字。
    /// 这是 cezzu-rule 格式唯一支持的占位符。
    public func resolvedSearchURL(for keyword: String) -> URL? {
        let encoded =
            keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let resolved = searchURL.replacingOccurrences(of: "@keyword", with: encoded)
        return URL(string: resolved)
    }

    /// 是否需要在播放阶段为这个规则启用本地反代（即规则要求自定义 Referer 或 UA）。
    public var needsHeaderInjection: Bool {
        !referer.isEmpty || !userAgent.isEmpty
    }
}
