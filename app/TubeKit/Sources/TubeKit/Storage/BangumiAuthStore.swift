import Foundation
import Observation
import os

/// Bangumi 登录态。两条登录路径：
///
/// 1. **OAuth**：需要构建时注入 client_id / client_secret（见 `BangumiOAuthConfig`），
///    走 `ASWebAuthenticationSession` 拿授权码再换令牌，可自动续期。
/// 2. **Access Token**：用户在 https://next.bgm.tv/demo/access-token 生成个人令牌粘贴进来。
///    零配置可用，但到期需要重新粘贴（bgm 不给这种令牌发 refresh_token）。
///
/// token 落 Keychain，用户资料落 UserDefaults（仅昵称 / 头像，方便冷启动秒显）。
/// token 的持久化后端。默认 Keychain；单测注入内存实现。
public protocol BangumiTokenStorage: Sendable {
    func load() -> Data?
    func save(_ data: Data) throws
    func remove() throws
}

/// Keychain 实现。
public struct KeychainTokenStorage: BangumiTokenStorage {
    public let account: String

    public init(account: String = "bangumi.token") {
        self.account = account
    }

    public func load() -> Data? { KeychainStore.get(account: account) }
    public func save(_ data: Data) throws { try KeychainStore.set(data, account: account) }
    public func remove() throws { try KeychainStore.remove(account: account) }
}

/// 内存实现，进程结束即丢。
public final class InMemoryTokenStorage: BangumiTokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init(initial: Data? = nil) {
        self.data = initial
    }

    public func load() -> Data? { lock.withLock { data } }
    public func save(_ data: Data) throws { lock.withLock { self.data = data } }
    public func remove() throws { lock.withLock { data = nil } }
}

@MainActor
@Observable
public final class BangumiAuthStore {
    /// OAuth 流程日志。只记环节和错误，不记 code / token。
    nonisolated static let log = Logger(subsystem: "com.nembx.tube", category: "bangumi-oauth")

    public private(set) var token: BangumiToken?
    public private(set) var user: BangumiUser?
    public private(set) var isAuthenticating: Bool = false
    public private(set) var lastError: String?

    public let oauthConfig: BangumiOAuthConfig
    private let api: BangumiAccountAPIProtocol
    private let oauth: BangumiOAuthClient
    private let defaults: UserDefaults
    private let storage: BangumiTokenStorage
    private var refreshTask: Task<BangumiToken, any Error>?

    nonisolated public static let userDefaultsKey = "tube.bangumi.user"

    public init(
        api: BangumiAccountAPIProtocol = BangumiAPIClient.shared,
        oauthConfig: BangumiOAuthConfig = .fromBundle(),
        defaults: UserDefaults = .standard,
        storage: BangumiTokenStorage = KeychainTokenStorage(),
        session: URLSession? = nil
    ) {
        self.api = api
        self.oauthConfig = oauthConfig
        self.oauth = BangumiOAuthClient(config: oauthConfig, session: session)
        self.defaults = defaults
        self.storage = storage
        restore()
    }

    public var isLoggedIn: Bool { token != nil }

    /// OAuth 入口是否可见。没配 client 凭证时只留手动令牌。
    public var supportsOAuth: Bool { oauthConfig.isConfigured }

    // MARK: - Login

    /// 手动粘贴 Access Token。先打一次 `/v0/me` 验证，验证不过不落盘。
    public func login(accessToken raw: String) async -> Bool {
        let accessToken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            lastError = "令牌不能为空"
            return false
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let me = try await api.me(token: accessToken)
            let token = BangumiToken(
                accessToken: accessToken,
                refreshToken: "",
                expiresAt: .distantFuture,
                userID: me.id
            )
            apply(token: token, user: me)
            lastError = nil
            return true
        } catch {
            lastError = Self.describe(error)
            return false
        }
    }

    /// OAuth 回调里拿到的授权码。
    public func login(authorizationCode code: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            Self.log.info("exchanging authorization code")
            let token = try await oauth.exchange(code: code)
            Self.log.info("token received, fetching /v0/me")
            let me = try await api.me(token: token.accessToken)
            apply(token: token, user: me)
            lastError = nil
            Self.log.info("login complete for user id \(me.id)")
            return true
        } catch {
            Self.log.error("code exchange failed: \(Self.describe(error), privacy: .public)")
            lastError = Self.describe(error)
            return false
        }
    }

    /// 授权页 URL；`state` 由调用方生成并在回调里核对。
    public func makeAuthorizeURL(state: String) async -> URL? {
        await oauth.makeAuthorizeURL(state: state)
    }

    /// 本轮 OAuth 的 state。`beginOAuth` 写入，回调消费后清掉；
    /// 同时也是「有没有一轮授权在进行」的标志，`onOpenURL` 据此决定要不要接这个 URL。
    public private(set) var pendingOAuthState: String?

    /// 开始一轮 OAuth：生成 state、拼授权页 URL。没配凭证返回 nil。
    public func beginOAuth() async -> URL? {
        guard supportsOAuth else { return nil }
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = await oauth.makeAuthorizeURL(state: state) else { return nil }
        pendingOAuthState = state
        lastError = nil
        Self.log.info("begin: authorize at \(url.host ?? "?", privacy: .public), expecting callback \(self.oauthConfig.redirectURI, privacy: .public)")
        return url
    }

    /// 这个 URL 是不是我们的 OAuth 回调（scheme + host 对得上）。
    public func isOAuthCallback(_ url: URL) -> Bool {
        guard let expected = URL(string: oauthConfig.redirectURI) else { return false }
        return url.scheme?.lowercased() == expected.scheme?.lowercased()
            && (url.host ?? "").lowercased() == (expected.host ?? "").lowercased()
    }

    /// 处理回调 URL：校验、换令牌、拉资料。授权窗口和 `onOpenURL` 两条路都汇到这里，
    /// 谁先到谁消费 `pendingOAuthState`，第二个到的直接返回 false，不会重复换码。
    @discardableResult
    public func handleCallbackURL(_ url: URL) async -> Bool {
        let shape = "\(url.scheme ?? "?")://\(url.host ?? "?")\(url.path) keys=\((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name))"
        guard isOAuthCallback(url) else {
            Self.log.notice("callback ignored (not ours): \(shape, privacy: .public)")
            return false
        }
        guard pendingOAuthState != nil else {
            Self.log.notice("callback ignored (no OAuth in progress / already consumed): \(shape, privacy: .public)")
            return false
        }
        Self.log.info("callback accepted: \(shape, privacy: .public)")
        let code: String
        do {
            code = try Self.extractCode(from: url, expectedState: pendingOAuthState)
        } catch {
            pendingOAuthState = nil
            lastError = Self.describe(error)
            Self.log.error("callback rejected: \(Self.describe(error), privacy: .public)")
            return false
        }
        pendingOAuthState = nil
        return await login(authorizationCode: code)
    }

    /// 从回调 URL 里取 `code`。`state` 带了才核对，bgm 没承诺回传它。
    nonisolated public static func extractCode(from url: URL, expectedState: String?) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let expectedState,
            let state = items.first(where: { $0.name == "state" })?.value,
            !state.isEmpty,
            state != expectedState
        {
            throw BangumiAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw BangumiAuthError.callbackMissingCode
        }
        return code
    }

    /// 用户关掉了授权窗口 / 流程中断，清掉本轮 state。
    public func cancelOAuth() {
        pendingOAuthState = nil
    }

    public func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        token = nil
        user = nil
        lastError = nil
        try? storage.remove()
        defaults.removeObject(forKey: Self.userDefaultsKey)
    }

    /// 重新拉一次用户资料（昵称 / 头像可能变）。
    public func refreshUser() async {
        guard let accessToken = try? await validAccessToken() else { return }
        if let me = try? await api.me(token: accessToken) {
            user = me
            persistUser(me)
        }
    }

    // MARK: - Token

    /// 拿一个当前可用的 access_token，过期则先续期。续期失败抛错并清掉登录态
    /// （refresh_token 已失效，留着只会每次请求都失败）。
    public func validAccessToken() async throws -> String {
        guard let token else { throw BangumiAuthError.notLoggedIn }
        guard token.isExpired() else { return token.accessToken }
        guard token.canRefresh else {
            // 手动令牌到期：无法续期，直接登出让用户重新粘贴。
            logout()
            throw BangumiAuthError.expired
        }
        // 多个请求同时发现过期时只刷新一次。
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let task = Task<BangumiToken, any Error> { [oauth] in
            try await oauth.refresh(token)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            apply(token: refreshed, user: user)
            return refreshed.accessToken
        } catch {
            logout()
            throw BangumiAuthError.expired
        }
    }

    /// OAuth 窗口这类在 store 之外发生的错误，交回来统一展示。
    public func reportError(_ error: any Error) {
        lastError = Self.describe(error)
    }

    /// 请求拿到 401 时调用：登录态已失效。
    public func handleUnauthorized() {
        // 先登出再写错误：`logout()` 会顺手清掉 lastError。
        logout()
        lastError = "登录已失效，请重新登录"
    }

    // MARK: - Persistence

    private func apply(token: BangumiToken, user: BangumiUser?) {
        self.token = token
        self.user = user
        if let data = try? JSONEncoder().encode(token) {
            try? storage.save(data)
        }
        if let user { persistUser(user) }
    }

    private func persistUser(_ user: BangumiUser) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: Self.userDefaultsKey)
        }
    }

    private func restore() {
        if let data = storage.load(),
            let stored = try? JSONDecoder().decode(BangumiToken.self, from: data)
        {
            token = stored
        }
        if let data = defaults.data(forKey: Self.userDefaultsKey),
            let stored = try? JSONDecoder().decode(BangumiUser.self, from: data)
        {
            user = stored
        }
        // 只有 token 没有资料（老版本 / Keychain 残留）时 user 为 nil，UI 会显示占位，
        // 并在下一次 `refreshUser` 后补齐。
    }

    static func describe(_ error: any Error) -> String {
        if let apiError = error as? BangumiAPIError {
            switch apiError {
            case .http(let status) where status == 401:
                return "令牌无效或已过期"
            default:
                return apiError.userMessage
            }
        }
        if let authError = error as? BangumiAuthError {
            return authError.userMessage
        }
        return error.localizedDescription
    }
}

public enum BangumiAuthError: Error, Hashable, Sendable {
    case notLoggedIn
    case expired
    case oauthNotConfigured
    case stateMismatch
    case callbackMissingCode
    case cancelled

    public var userMessage: String {
        switch self {
        case .notLoggedIn: return "尚未登录 Bangumi"
        case .expired: return "登录已过期，请重新登录"
        case .oauthNotConfigured: return "未配置 Bangumi OAuth 凭证"
        case .stateMismatch: return "授权回调校验失败（state 不一致）"
        case .callbackMissingCode: return "授权回调里没有 code，请检查 bgm 后台的回调地址是否为 nembx-tube://bangumi-auth"
        case .cancelled: return "已取消"
        }
    }
}
