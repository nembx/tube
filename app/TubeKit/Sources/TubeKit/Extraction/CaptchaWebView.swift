import Foundation
import SwiftUI
@preconcurrency import WebKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// 用 `WKWebView` 托管一个可交互的验证码页面。
/// 用户在页面里完成人机校验后，宿主 sheet 调用 `collectCookies()` 把当前站点的 cookie
/// 塞进 `PluginCookieStore`，然后由调用方关闭 sheet 并重试请求。
///
/// 跨平台：iOS 走 `UIViewRepresentable`，macOS 走 `NSViewRepresentable`。
/// 这里只做一层最薄的 bridge，不写平台专属业务逻辑。
@MainActor
public struct CaptchaWebView {

    /// 要加载的页面（通常是搜索 URL 或详情 URL）。
    public let url: URL
    /// 规则的 User-Agent，没有就随机选一个 —— 和 `HTTPClient` 行为对齐。
    public let userAgent: String
    /// WebView 可用后回调，宿主拿着它调 `collectCookies`。
    public let onReady: (CaptchaWebViewHandle) -> Void

    public init(
        url: URL,
        userAgent: String,
        onReady: @escaping (CaptchaWebViewHandle) -> Void
    ) {
        self.url = url
        self.userAgent = userAgent.isEmpty ? RandomUA.next() : userAgent
        self.onReady = onReady
    }
}

/// 宿主侧句柄：抹平 WKWebView 的直接依赖，只暴露"拿 cookie"这一件事。
@MainActor
public final class CaptchaWebViewHandle {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    /// 读当前 webView 里匹配指定 host 的全部 cookie。
    public func collectCookies(matching host: String) async -> [HTTPCookie] {
        guard let webView else { return [] }
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let lower = host.lowercased()
        return all.filter { cookie in
            let domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") {
                let bare = String(domain.dropFirst())
                return lower == bare || lower.hasSuffix("." + bare)
            }
            return lower == domain || lower.hasSuffix("." + domain)
        }
    }

    public func reload() {
        webView?.reload()
    }
}

// MARK: - SwiftUI bridges

#if canImport(UIKit)

    extension CaptchaWebView: UIViewRepresentable {
        public func makeUIView(context: Context) -> WKWebView {
            let view = makeWebView()
            onReady(CaptchaWebViewHandle(webView: view))
            var req = URLRequest(url: url)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            view.load(req)
            return view
        }
        public func updateUIView(_ uiView: WKWebView, context: Context) {}
    }

#elseif canImport(AppKit)

    extension CaptchaWebView: NSViewRepresentable {
        public func makeNSView(context: Context) -> WKWebView {
            let view = makeWebView()
            onReady(CaptchaWebViewHandle(webView: view))
            var req = URLRequest(url: url)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            view.load(req)
            return view
        }
        public func updateNSView(_ nsView: WKWebView, context: Context) {}
    }

#endif

extension CaptchaWebView {
    fileprivate func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        #if canImport(UIKit)
            cfg.allowsInlineMediaPlayback = true
        #endif
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.customUserAgent = userAgent
        return webView
    }
}
