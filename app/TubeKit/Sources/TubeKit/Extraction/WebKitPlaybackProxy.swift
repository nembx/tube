import Foundation
import Network
@preconcurrency import WebKit

/// 给 WKWebView 的数据存储配置上游代理。参考 Kazumi 的 webview proxy 思路：
/// 只作用于播放相关的 WebView（嗅探 / 验证码），不动 App 的其它网络请求。
///
/// `WKWebsiteDataStore.proxyConfigurations` 在 iOS 17 / macOS 14 起可用，
/// 参数是 `nw_proxy_config_t`，按主机端口精确设置。
enum WebKitPlaybackProxy {
    static func apply(to dataStore: WKWebsiteDataStore, defaults: UserDefaults = .standard) {
        guard
            let url = PlaybackProxySettings.proxyURL(from: defaults),
            let host = url.host,
            let port = url.port.flatMap({ NWEndpoint.Port(rawValue: UInt16(clamping: $0)) })
        else { return }
        let configuration = ProxyConfiguration(
            httpCONNECTProxy: NWEndpoint.hostPort(host: .init(host), port: port)
        )
        dataStore.proxyConfigurations = [configuration]
    }
}
