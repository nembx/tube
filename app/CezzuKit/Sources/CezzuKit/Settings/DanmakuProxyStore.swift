import Foundation

/// 用户在「弹幕设置」里配置的 DanDanPlay 反向代理。
/// 开启后所有 DanDanPlay 请求都直接打到代理域名，不再附带 AppId / 签名头 —— 由代理服务端负责签名并转发。
public enum DanmakuProxyStore {
    public static let useProxyKey = "cezzu.dandanplay.useProxy"
    public static let proxyURLKey = "cezzu.dandanplay.proxyURL"

    public static let useProxyDefault = false

    public struct Snapshot: Sendable {
        public let useProxy: Bool
        public let proxyURL: String

        public init(useProxy: Bool, proxyURL: String) {
            self.useProxy = useProxy
            self.proxyURL = proxyURL
        }

        /// 返回归一化后的代理 base URL（去掉末尾斜杠、仅保留 scheme://host[:port]）。
        /// 开关关闭或 URL 不合法时返回 nil。
        public var resolvedBaseURL: URL? {
            guard useProxy else { return nil }
            let trimmed = proxyURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !trimmed.isEmpty else { return nil }
            guard let url = URL(string: trimmed),
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                url.host?.isEmpty == false
            else {
                return nil
            }
            return url
        }
    }

    public static func snapshot(from defaults: UserDefaults = .standard) -> Snapshot {
        Snapshot(
            useProxy: defaults.object(forKey: useProxyKey) as? Bool ?? useProxyDefault,
            proxyURL: defaults.string(forKey: proxyURLKey) ?? ""
        )
    }
}
