import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OAuth 应用配置。client_id / client_secret 由使用者在构建时通过
/// `LocalSecrets.xcconfig` 注入（与 DanDanPlay 凭证同一套机制），
/// 因为 Bangumi 的 OAuth 应用必须由本人注册，仓库不能带一份公共凭证。
public struct BangumiOAuthConfig: Sendable {
    public let clientID: String
    public let clientSecret: String
    /// 回调地址。必须和 bgm 后台登记的一致，App 用它的 scheme 接住 `?code=`。
    public let redirectURI: String
    public let authorizeURL: URL
    public let tokenURL: URL

    public init(
        clientID: String,
        clientSecret: String,
        redirectURI: String,
        authorizeURL: URL = URL(string: "https://bgm.tv/oauth/authorize")!,
        tokenURL: URL = URL(string: "https://bgm.tv/oauth/access_token")!
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
    }

    /// 配置是否可用（两个必填项都非空）。
    public var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 回调 scheme —— ASWebAuthenticationSession 用它识别回调。
    public var callbackScheme: String? {
        guard let url = URL(string: redirectURI), let scheme = url.scheme else { return nil }
        return scheme
    }

    /// 从 Info.plist 读取配置。缺省时 `isConfigured == false`，UI 会隐藏 OAuth 入口，
    /// 只留「手动填 Access Token」那条路。
    /// 按站点推导授权页与换 token 地址（官方：bgm.tv；镜像：api.<host>）。
    public static func forSite(_ site: BangumiSite, bundle: Bundle = .main) -> BangumiOAuthConfig {
        var config = fromBundle(bundle)
        return BangumiOAuthConfig(
            clientID: config.clientID,
            clientSecret: config.clientSecret,
            redirectURI: config.redirectURI,
            authorizeURL: site.authorizeURL,
            tokenURL: site.tokenURL
        )
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> BangumiOAuthConfig {
        func string(_ key: String) -> String {
            (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        // xcconfig 会把 `//` 当注释，经它注入的回调地址可能被截成 `nembx-tube:`；
        // 不像完整 URL 的值一律回退默认，别让一个残值把整条 OAuth 弄哑。
        let redirect = string("BangumiRedirectURI")
        return BangumiOAuthConfig(
            clientID: string("BangumiClientID"),
            clientSecret: string("BangumiClientSecret"),
            redirectURI: redirect.contains("://") ? redirect : defaultRedirectURI
        )
    }

    public static let defaultRedirectURI = "nembx-tube://bangumi-auth"
}

/// 持久化的令牌。存 Keychain，序列化成 JSON。
public struct BangumiToken: Hashable, Sendable, Codable {
    public var accessToken: String
    public var refreshToken: String
    /// 过期时刻。`expires_in` 是相对秒数，落地时换算成绝对时间。
    public var expiresAt: Date
    public var userID: Int

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: Int = 0) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
    }

    /// 是否已过期。提前 1 小时算过期（与 animeko 一致）：access_token 有效期 7 天，
    /// 宁可早点刷新，也别让请求发出的瞬间刚好失效。
    public func isExpired(now: Date = .now, leeway: TimeInterval = 3600) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }

    /// 还能用 refresh_token 续期。
    public var canRefresh: Bool {
        !refreshToken.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// token 端点返回体。
struct BangumiTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let tokenType: String?
    let refreshToken: String?
    let userID: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case userID = "user_id"
    }
}

/// Bangumi OAuth 客户端：授权码换取令牌、刷新令牌。
public actor BangumiOAuthClient {
    private let config: BangumiOAuthConfig
    private let session: URLSession

    public init(config: BangumiOAuthConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: cfg)
        }
    }

    /// 拼接授权页 URL。调用方用 `ASWebAuthenticationSession` 打开它。
    public func makeAuthorizeURL(state: String) -> URL? {
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// 用授权码换令牌。
    public func exchange(code: String) async throws -> BangumiToken {
        try await requestToken([
            "grant_type": "authorization_code",
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "code": code,
            "redirect_uri": config.redirectURI,
        ])
    }

    /// 用 refresh_token 续期。
    public func refresh(_ token: BangumiToken) async throws -> BangumiToken {
        var next = try await requestToken([
            "grant_type": "refresh_token",
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "refresh_token": token.refreshToken,
            // bgm 文档把 redirect_uri 列为 refresh 的必填项，和换码时保持一致。
            "redirect_uri": config.redirectURI,
        ])
        // bgm 刷新响应有时不带 user_id，沿用旧值。
        if next.userID == 0 { next.userID = token.userID }
        return next
    }

    private func requestToken(_ fields: [String: String]) async throws -> BangumiToken {
        var req = URLRequest(url: config.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(BangumiAPIClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(fields)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw BangumiAPIError.transport(message: "non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw BangumiAPIError.http(status: http.statusCode)
        }
        do {
            let decoded = try JSONDecoder().decode(BangumiTokenResponse.self, from: data)
            return BangumiToken(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken ?? "",
                expiresAt: Date().addingTimeInterval(decoded.expiresIn),
                userID: decoded.userID ?? 0
            )
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }
}
