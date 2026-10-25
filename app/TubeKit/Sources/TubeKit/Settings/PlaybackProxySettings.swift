import Foundation

/// 播放代理设置。参考 Kazumi 的 `ProxyUtils` / animeko 的 `ProxyConfig`：
/// 用户填一个 HTTP 代理（本地 Clash 之类），**只作用于播放链路** ——
/// WebView 嗅探和视频流请求都走它，不影响 App 其它网络请求。
///
/// 适用的场景：资源站或它的视频 CDN 在境外，不开全局代理时「能嗅探到地址、
/// 但一直缓冲」。这时在设置里填 `http://127.0.0.1:7890` 即可。
public enum PlaybackProxySettings {
    public static let enabledKey = "tube.playback.proxyEnabled"
    public static let urlKey = "tube.playback.proxyURL"
    /// 与 Kazumi / animeko 的默认值一致。
    public static let urlDefault = "http://127.0.0.1:7890"
    public static let enabledDefault = false

    /// 解析后的代理地址；未启用或地址非法时返回 nil。
    public static func proxyURL(from defaults: UserDefaults = .standard) -> URL? {
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? enabledDefault
        guard enabled else { return nil }
        let raw = defaults.string(forKey: urlKey) ?? urlDefault
        guard let parsed = parse(raw) else { return nil }
        return URL(string: "http://\(parsed.host):\(parsed.port)")
    }

    /// Kazumi 同款解析：接受 `http://host:port` / `https://host:port` / `host:port`。
    public static func parse(_ raw: String) -> (host: String, port: Int)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("http://") {
            text = String(text.dropFirst(7))
        } else if text.lowercased().hasPrefix("https://") {
            text = String(text.dropFirst(8))
        }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let port = Int(parts[1]), (1...65535).contains(port) else {
            return nil
        }
        return (String(parts[0]), port)
    }

    public static func isValid(_ raw: String) -> Bool { parse(raw) != nil }

    /// 给本地反代的 `URLSession` 配上游代理。没启用时原样返回。
    public static func apply(to configuration: URLSessionConfiguration, defaults: UserDefaults = .standard) {
        guard let url = proxyURL(from: defaults), let host = url.host, let port = url.port else { return }
        configuration.connectionProxyDictionary = [
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port,
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
        ]
    }
}
