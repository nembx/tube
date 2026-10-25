import Foundation

/// Bangumi 图片镜像设置。
///
/// `lain.bgm.tv`（Bangumi 的图床）在国内经常被 Cloudflare 挡住：接口数据能回，
/// 封面却全部空白。方案参考 Kazumi 的 `BangumiImageUrlRewriter`：
/// 把图床地址交给公开图片代理，而不是新建一个反代域名。
///
/// 支持两种镜像写法：
/// - **代理式**（默认，Kazumi 同款）：`https://wsrv.nl/?url=<去掉 scheme 的原地址>`。
///   适合 wsrv.nl 这类「通过 query 传目标 URL」的图片代理。
/// - **前缀式**：`https://img.example.com` → `https://img.example.com<原路径>`。
///   适合自建反代（nginx / Cloudflare Worker）。
///
/// **回落策略**：先镜像、失败再直连原地址 —— 反过来不行：直连要等满超时才轮到镜像，
/// 在国内时延下体验太差；而镜像本来就是给国内用户用的。
public enum BangumiImageMirrorSettings {
    public static let mirrorKey = "tube.bangumi.imageMirror"
    /// 默认与 Kazumi 一致。填 `off` 表示关闭镜像、只直连。
    public static let mirrorDefault = "https://wsrv.nl"
    public static let disabledValues: Set<String> = ["off", "none", "direct", "直连"]

    /// Kazumi 同款：wsrv.nl 需要不带 scheme 的源地址作为 `url` 参数。
    public static let proxyStyleHosts: Set<String> = ["wsrv.nl", "images.weserv.nl"]

    /// 会被改写的图床主机。
    public static let mirroredHosts: Set<String> = ["lain.bgm.tv"]

    /// `api.bgm.tv/v0/{kind}/{id}/image` 也是图片接口，Kazumi 一并改写。
    public static let apiImageKinds: Set<String> = ["subjects", "characters", "persons"]

    /// 用户配置的镜像。返回空串表示未配置或显式关闭。
    public static func mirrorPrefix(from defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: mirrorKey) ?? mirrorDefault
        return sanitize(raw)
    }

    /// 规范化：去空白、去末尾斜杠、校验 http(s)；`off` 等关闭值返回空串。
    public static func sanitize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if disabledValues.contains(value.lowercased()) { return "" }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host?.isEmpty == false
        else {
            return ""
        }
        return value
    }

    public static func shouldMirror(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if mirroredHosts.contains(host) { return true }
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
    public static func mirroredURL(for url: URL, mirrorPrefix: String) -> URL? {
        let prefix = mirrorPrefix.isEmpty ? "" : sanitize(mirrorPrefix)
        guard !prefix.isEmpty, shouldMirror(url) else { return nil }
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
    public static func candidateURLs(for url: URL, mirrorPrefix: String) -> [URL] {
        if let mirrored = mirroredURL(for: url, mirrorPrefix: mirrorPrefix) {
            return [mirrored, url]
        }
        return [url]
    }
}
