import Foundation

/// Bangumi 图片地址改写。
///
/// 优先级：
/// 1. **图片镜像设置**（`tube.bangumi.imageMirror`）：`off` = 直连；`auto`（默认）= 跟随
///    「Bangumi 服务」站点；其它值 = 显式代理（`https://wsrv.nl` 或自建前缀）。
/// 2. 站点镜像：选中 `bangumi.lat` 时，`lain.bgm.tv` 改写成 `lain.bangumi.lat`。
///
/// 两种镜像写法：
/// - **子域式**（`auto` + 镜像站）：只替换 host，路径不变。
/// - **代理式**（`https://wsrv.nl`）：`?url=<去掉 scheme 的原地址>`，gif 加 `n=-1`（Kazumi 同款）。
/// - **前缀式**（`https://img.example.com`）：`前缀 + 原路径`。
///
/// **回落策略**：先镜像、失败再直连原地址 —— 反过来不行：直连要等满超时才轮到镜像，
/// 在国内时延下体验太差；而镜像本来就是给国内用户用的。
public enum BangumiImageMirrorSettings {
    public static let mirrorKey = "tube.bangumi.imageMirror"
    /// `auto`：跟随「Bangumi 服务」站点。
    public static let mirrorDefault = "auto"
    public static let disabledValues: Set<String> = ["off", "none", "direct", "直连"]

    /// wsrv.nl 需要不带 scheme 的源地址作为 `url` 参数。
    public static let proxyStyleHosts: Set<String> = ["wsrv.nl", "images.weserv.nl"]

    /// 会被改写的图床主机。镜像站返回的本来就是 `lain.<镜像域名>`，
    /// 也要认，否则在「直连 / wsrv」模式下镜像图片无法再被改写。
    public static func isImageHost(_ host: String) -> Bool {
        host == "lain.bgm.tv" || host.hasPrefix("lain.")
    }

    /// `api.bgm.tv/v0/{kind}/{id}/image` 也是图片接口，一并改写。
    public static let apiImageKinds: Set<String> = ["subjects", "characters", "persons"]

    /// 解析设置：空串表示关闭镜像。
    public static func mirrorPrefix(from defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: mirrorKey) ?? mirrorDefault
        return sanitize(raw)
    }

    /// 规范化：`auto` / `off` 原样保留语义；URL 去空白、去末尾斜杠并校验。
    public static func sanitize(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased() == "auto" { return "auto" }
        if disabledValues.contains(value.lowercased()) { return "" }
        var trimmed = value
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host?.isEmpty == false
        else {
            return ""
        }
        return trimmed
    }

    public static func shouldMirror(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if isImageHost(host) { return true }
        guard host == "api.bgm.tv" else { return false }
        // /v0/subjects/123/image
        let segments = url.path.split(separator: "/").map(String.init)
        return segments.count == 4
            && segments[0] == "v0"
            && apiImageKinds.contains(segments[1])
            && Int(segments[2]) != nil
            && segments[3] == "image"
    }

    /// 改写后的镜像地址；不需要或无法改写时返回 nil。
    ///
    /// - Parameter site: 当前选中的 Bangumi 站点（`auto` 模式据此推导图床）。
    public static func mirroredURL(
        for url: URL,
        mirrorPrefix: String,
        site: BangumiSite = BangumiSiteSettings.selectedSite()
    ) -> URL? {
        let prefix = mirrorPrefix.isEmpty ? "" : sanitize(mirrorPrefix)
        guard !prefix.isEmpty, shouldMirror(url) else { return nil }

        // auto：官方站点直连；镜像站点替换成 lain.<host>。
        if prefix == "auto" {
            guard !site.isOfficial else { return nil }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            components.host = site.imageDomain.host
            components.scheme = "https"
            return components.url
        }

        guard let base = URL(string: prefix), let host = base.host?.lowercased() else { return nil }

        if proxyStyleHosts.contains(host) {
            // wsrv.nl 风格：url=<host><path>?<query>，不带 scheme。
            let source = (url.host ?? "") + url.path + (url.query.map { "?\($0)" } ?? "")
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "url", value: source))
            // gif 要拿原始帧，Kazumi 用 n=-1 关闭帧数限制。
            if url.path.lowercased().hasSuffix(".gif") {
                items.append(URLQueryItem(name: "n", value: "-1"))
            }
            components.queryItems = items
            return components.url
        }

        // 前缀式：镜像地址 + 原路径。
        var path = url.path
        if !path.hasPrefix("/") { path = "/" + path }
        guard var components = URLComponents(string: prefix + path) else { return nil }
        components.query = url.query
        return components.url
    }

    /// 按「镜像优先、原地址兜底」列出要尝试的地址。未配置镜像时只有原地址。
    public static func candidateURLs(
        for url: URL,
        mirrorPrefix: String,
        site: BangumiSite = BangumiSiteSettings.selectedSite()
    ) -> [URL] {
        if let mirrored = mirroredURL(for: url, mirrorPrefix: mirrorPrefix, site: site) {
            return [mirrored, url]
        }
        return [url]
    }
}
