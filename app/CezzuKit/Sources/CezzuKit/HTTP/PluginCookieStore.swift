import Foundation

/// 按规则 name 维度在内存里缓存 cookie。
/// 验证码通过后，把 WKWebView 里拿到的 cookie 塞进来，下次 `HTTPClient` 发请求时
/// 会自动附在 `Cookie` 头上，服务端就认可当前会话。
///
/// 不落盘：App 重启 / 用户切账号时全部丢弃，和 Kazumi 行为一致。
public actor PluginCookieStore {
    public static let shared = PluginCookieStore()

    /// ruleName -> [HTTPCookie]
    private var cookiesByRule: [String: [HTTPCookie]] = [:]

    public init() {}

    /// 整套覆盖（验证码成功后常用）。
    public func set(_ cookies: [HTTPCookie], for ruleName: String) {
        cookiesByRule[ruleName] = cookies
    }

    /// 合并：同名 cookie 会被新值覆盖。
    public func merge(_ cookies: [HTTPCookie], for ruleName: String) {
        var current = cookiesByRule[ruleName] ?? []
        for cookie in cookies {
            current.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            current.append(cookie)
        }
        cookiesByRule[ruleName] = current
    }

    public func cookies(for ruleName: String) -> [HTTPCookie] {
        cookiesByRule[ruleName] ?? []
    }

    /// 给 URL 过滤出可用 cookie（匹配 domain / path / secure）。
    public func cookies(for ruleName: String, matching url: URL) -> [HTTPCookie] {
        let all = cookiesByRule[ruleName] ?? []
        guard let host = url.host?.lowercased() else { return [] }
        let isSecure = url.scheme?.lowercased() == "https"
        let path = url.path.isEmpty ? "/" : url.path
        return all.filter { cookie in
            let domain = cookie.domain.lowercased()
            let domainMatches: Bool = {
                if domain.hasPrefix(".") {
                    let bare = String(domain.dropFirst())
                    return host == bare || host.hasSuffix("." + bare) || host == domain
                }
                return host == domain
            }()
            guard domainMatches else { return false }
            guard path.hasPrefix(cookie.path) else { return false }
            if cookie.isSecure, !isSecure { return false }
            return true
        }
    }

    public func clear(_ ruleName: String) {
        cookiesByRule.removeValue(forKey: ruleName)
    }

    public func clearAll() {
        cookiesByRule.removeAll()
    }
}
