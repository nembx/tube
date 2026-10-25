import Foundation

/// Bangumi 服务站点。默认官方 `bgm.tv`；国内直连经常被挡，可以切到镜像（如 `bangumi.lat`）。
///
/// 一个站点由三个派生地址组成，镜像站按镜像站的规则推导：
/// - API：`api.<host>`（官方是 `api.bgm.tv`，`next.bgm.tv` 只在官方上使用）
/// - 图床：`lain.<host>`（官方是 `lain.bgm.tv`）
/// - 网页 / OAuth 授权页：`<host>`（官方是 `bgm.tv`）
public struct BangumiSite: Hashable, Sendable, Identifiable, Codable {
    /// 用来展示与去重的稳定标识，就是 host。
    public let host: String
    public let name: String
    /// 官方站点：额外的 next.bgm.tv 热门接口可用。
    public let isOfficial: Bool

    public var id: String { host }

    public init(host: String, name: String, isOfficial: Bool = false) {
        self.host = host
        self.name = name
        self.isOfficial = isOfficial
    }

    public static let official = BangumiSite(host: "bgm.tv", name: "官方（bgm.tv）", isOfficial: true)
    /// 国内可直连的完整镜像：API / 图床 / 网页都有对应子域。
    public static let mirrorLat = BangumiSite(host: "bangumi.lat", name: "bangumi.lat 镜像")

    public static var presets: [BangumiSite] { [official, mirrorLat] }

    public var apiDomain: URL { URL(string: "https://api.\(host)")! }
    public var nextDomain: URL? { isOfficial ? URL(string: "https://next.bgm.tv") : nil }
    public var webDomain: URL { URL(string: "https://\(host)")! }
    public var imageDomain: URL { URL(string: "https://lain.\(host)")! }

    /// 授权页固定走官方 bgm.tv。
    ///
    /// 镜像站（bangumi.lat）的网页前面有 Anubis 反机器人验证，授权链路经过它后
    /// 回调参数容易变形 / 授权码超过 60 秒有效期，实测换 token 会 400。
    /// OAuth 只在登录时用一次，固定官方最稳；镜像只承担日常 API 与图床。
    public var authorizeURL: URL { URL(string: "https://bgm.tv/oauth/authorize")! }

    /// 换 token 的地址，固定走官方。
    ///
    /// 实测镜像站只代理 `/v0/`：`api.bangumi.lat/oauth/access_token` 返回 400；
    /// 网页镜像的 token 端点又被 Anubis 挡住。OAuth token 端点是 App 自己发的一次
    /// 普通 HTTPS 请求，不需要用户直连，所以固定用官方地址即可。
    public var tokenURL: URL { URL(string: "https://bgm.tv/oauth/access_token")! }

    /// 短评 / 长评 / 角色 / 制作人员等网页 HTML 的地址。
    ///
    /// `api.bangumi.lat` 只代理 JSON API，网页内容要走网页镜像；官方则用 bgm.tv。
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

    public static func selectedSite(from defaults: UserDefaults = .standard) -> BangumiSite {
        let host = defaults.string(forKey: selectedHostKey) ?? ""
        guard !host.isEmpty else { return .official }
        return allSites(from: defaults).first { $0.host == host } ?? .official
    }

    /// 内置站 + 用户添加的站，去重，官方永远排第一。
    public static func allSites(from defaults: UserDefaults = .standard) -> [BangumiSite] {
        var seen = Set<String>()
        var result: [BangumiSite] = []
        for site in BangumiSite.presets + customSites(from: defaults) where seen.insert(site.host).inserted {
            result.append(site)
        }
        return result
    }

    public static func customSites(from defaults: UserDefaults = .standard) -> [BangumiSite] {
        guard let data = defaults.data(forKey: customSitesKey),
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
