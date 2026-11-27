import Foundation

/// Bangumi 服务站点。默认官方 `bgm.tv`；国内直连经常被挡，可以切到镜像（如 `bangumi.lat`）。
///
/// 官方与手动添加的镜像按以下规则推导地址，目录镜像使用目录公布的服务域名：
/// - API：`api.<host>`（官方是 `api.bgm.tv`）；`next.<host>` 的 /p1 接口（热门、短评、
///   长评、单集吐槽）镜像站同样代理，实测 next.bangumi.lat 与 next.bgm.tv 返回一致
/// - 图床：`lain.<host>`（官方是 `lain.bgm.tv`）
/// - 网页 / OAuth 授权页：`<host>`（官方是 `bgm.tv`）
public struct BangumiSite: Hashable, Sendable, Identifiable, Codable {
    struct ServiceHosts: Hashable, Sendable, Codable {
        let api: String
        let next: String
        let image: String
        let web: String
    }

    /// 用来展示与去重的稳定标识，就是 host。
    public let host: String
    public let name: String
    /// 官方站点：OAuth 授权与换 token 只能在这里完成（见 `authorizeURL` / `tokenURL`）。
    public let isOfficial: Bool
    private let serviceHosts: ServiceHosts?

    public var id: String { host }

    public init(host: String, name: String, isOfficial: Bool = false) {
        self.host = host
        self.name = name
        self.isOfficial = isOfficial
        self.serviceHosts = nil
    }

    init(host: String, name: String, serviceHosts: ServiceHosts) {
        self.host = host
        self.name = name
        self.isOfficial = false
        self.serviceHosts = serviceHosts
    }

    public static let official = BangumiSite(host: "bgm.tv", name: "官方（bgm.tv）", isOfficial: true)
    /// 保留旧版本已选中的内置镜像。
    public static let mirrorLat = BangumiSite(host: "bangumi.lat", name: "bangumi.lat 镜像")

    public var apiDomain: URL { URL(string: "https://\(serviceHosts?.api ?? "api.\(host)")")! }
    /// /p1 接口。镜像站也代理它（2026-10 实测 next.bangumi.lat 的热门、短评、长评、
    /// 单集吐槽与官方逐字节一致），所以不再只给官方。
    public var nextDomain: URL { URL(string: "https://\(serviceHosts?.next ?? "next.\(host)")")! }
    public var webDomain: URL { URL(string: "https://\(serviceHosts?.web ?? host)")! }
    public var imageDomain: URL { URL(string: "https://\(serviceHosts?.image ?? "lain.\(host)")")! }

    /// 授权页固定走官方 bgm.tv。
    ///
    /// 2026-10 实测：镜像站整个网页层（含 /oauth/authorize）都在 Anubis 的 JavaScript
    /// 工作量证明之后，浏览器能自动通过，但换 token 的端点镜像根本没有代理（见 `tokenURL`），
    /// 所以授权页走镜像也完成不了登录。登录是一次性动作，固定官方；登录后的
    /// `/v0/me`、收藏、进度全部跟随站点走 `api.<host>`，镜像用户之后不再需要翻墙。
    public var authorizeURL: URL { URL(string: "https://bgm.tv/oauth/authorize")! }

    /// 换 token 的地址，固定走官方。
    ///
    /// 2026-10 实测：`api.bangumi.lat/oauth/access_token` 返回的是 HTML 错误页（不是
    /// OAuth 的 JSON `invalid_request`），`bangumi.lat/oauth/access_token` 被 Anubis 挡住；
    /// App 自己发的 POST 过不了工作量证明，所以这一步只能用官方地址。
    public var tokenURL: URL { URL(string: "https://bgm.tv/oauth/access_token")! }

    /// 网页 HTML 的地址，只作 /p1 接口不可用时的回落。
    ///
    /// 短评 / 长评 / 单集吐槽现在走 `nextDomain` 的 JSON 接口，镜像站可直达；
    /// 镜像的网页层在 Anubis 之后、App 抓不到，所以回落固定抓官方。
    public var webPageBase: URL { URL(string: "https://bgm.tv")! }

    /// 把任意合法 host 规范化成站点（用户手动添加镜像时用）。
    public static func parse(_ raw: String) -> BangumiSite? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        guard !text.isEmpty,
            text.contains("."),
            !text.contains(" "),
            text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else {
            return nil
        }
        if text == BangumiSite.official.host { return .official }
        if text == BangumiSite.mirrorLat.host { return .mirrorLat }
        return BangumiSite(host: text, name: text)
    }
}

/// 「Bangumi 服务」设置：站点列表 + 当前选中项。
///
/// 只影响 Bangumi 的 API / 图床 / 登录页，播放链路不受影响（那是「播放代理」的事）。
public enum BangumiSiteSettings {
    public static let selectedHostKey = "tube.bangumi.siteHost"
    public static let customSitesKey = "tube.bangumi.customSites"
    private static let mirrorSitesKey = "tube.bangumi.mirrorSites"

    public static func selectedSite(from defaults: UserDefaults = .standard) -> BangumiSite {
        let host = defaults.string(forKey: selectedHostKey) ?? ""
        guard !host.isEmpty else { return .official }
        return allSites(from: defaults).first { $0.host == host } ?? .official
    }

    /// 官方、目录镜像、手动镜像。同域名优先保留手动配置。
    public static func allSites(from defaults: UserDefaults = .standard) -> [BangumiSite] {
        let customSites = customSites(from: defaults)
        let customHosts = Set(customSites.map(\.host))
        let mirrorSites = storedSites(forKey: mirrorSitesKey, from: defaults)
            .filter { !customHosts.contains($0.host) }
        let legacy = BangumiSite.mirrorLat
        let legacySites = defaults.string(forKey: selectedHostKey) == legacy.host ? [legacy] : []
        var seen = Set<String>()
        return ([BangumiSite.official] + mirrorSites + customSites + legacySites).filter {
            seen.insert($0.host).inserted
        }
    }

    static func storeMirrorSites(_ sites: [BangumiSite], defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(sites), forKey: mirrorSitesKey)
    }

    public static func customSites(from defaults: UserDefaults = .standard) -> [BangumiSite] {
        storedSites(forKey: customSitesKey, from: defaults)
    }

    private static func storedSites(forKey key: String, from defaults: UserDefaults) -> [BangumiSite] {
        guard let data = defaults.data(forKey: key),
            let sites = try? JSONDecoder().decode([BangumiSite].self, from: data)
        else {
            return []
        }
        return sites
    }

    public static func select(_ site: BangumiSite, defaults: UserDefaults = .standard) {
        defaults.set(site.host, forKey: selectedHostKey)
    }

    /// 添加自定义镜像。已存在时返回 nil。
    @discardableResult
    public static func addCustomSite(_ raw: String, defaults: UserDefaults = .standard) -> BangumiSite? {
        guard let site = BangumiSite.parse(raw) else { return nil }
        guard !allSites(from: defaults).contains(where: { $0.host == site.host }) else { return nil }
        var sites = customSites(from: defaults)
        sites.append(site)
        if let data = try? JSONEncoder().encode(sites) {
            defaults.set(data, forKey: customSitesKey)
        }
        return site
    }

    public static func removeCustomSite(host: String, defaults: UserDefaults = .standard) {
        let sites = customSites(from: defaults).filter { $0.host != host }
        if let data = try? JSONEncoder().encode(sites) {
            defaults.set(data, forKey: customSitesKey)
        }
        if defaults.string(forKey: selectedHostKey) == host {
            defaults.removeObject(forKey: selectedHostKey)
        }
    }
}
