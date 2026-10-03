import Foundation
@preconcurrency import WebKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// `VideoExtractor` 的生产实现 —— 用一个 hidden `WKWebView` + 注入脚本嗅探。
///
/// 设计要点见 design.md D4：
///   1. 在 `atDocumentStart` 注入脚本 hook XHR / fetch / Response.text，命中条件
///      = body 起头 `#EXTM3U` 或 URL 路径 `.m3u8` 后缀 或 Range 请求且非黑名单扩展。
///   2. 在 `atDocumentEnd` 注入脚本扫 `<video>` / `<source>` 并装 MutationObserver。
///   3. 装一份 `WKContentRuleList` 屏广告。
///   4. 注册 `cezzuVideoSink` message handler，所有命中通过 `AsyncStream` 推给调用方。
///
/// 必须运行在 MainActor —— `WKWebView` 是主线程类型。
@MainActor
public final class WebViewVideoExtractor: NSObject, VideoExtractor {

    public override init() {
        super.init()
    }

    nonisolated public func extract(
        from url: URL,
        rule: CezzuRule
    ) -> AsyncStream<ExtractedMedia> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let session = await ExtractionSession.start(
                    url: url,
                    rule: rule,
                    continuation: continuation
                )
                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor in
                        await session.tearDown()
                    }
                }
            }
            _ = task
        }
    }
}

// MARK: - one extraction session

@MainActor
final class ExtractionSession: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    private let webView: WKWebView
    private let continuation: AsyncStream<ExtractedMedia>.Continuation
    /// 规则声明的视频 URL 过滤 / 改写；规则没写 `videoURLPattern` 时是恒等变换。
    private let videoFilter: RuleVideoFilter
    private var torn = false

    private init(
        webView: WKWebView,
        continuation: AsyncStream<ExtractedMedia>.Continuation,
        videoFilter: RuleVideoFilter
    ) {
        self.webView = webView
        self.continuation = continuation
        self.videoFilter = videoFilter
    }

    static func start(
        url: URL,
        rule: CezzuRule,
        continuation: AsyncStream<ExtractedMedia>.Continuation
    ) async -> ExtractionSession {
        let config = WKWebViewConfiguration()
        #if canImport(UIKit)
            config.allowsInlineMediaPlayback = true
        #endif
        config.mediaTypesRequiringUserActionForPlayback = []

        // 注入两段 JS
        if let startJS = WebViewVideoExtractor.loadResource(name: "inject_start", ext: "js") {
            let script = WKUserScript(
                source: startJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }
        if let endJS = WebViewVideoExtractor.loadResource(name: "inject_end", ext: "js") {
            let script = WKUserScript(
                source: endJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }

        // 注入广告 ContentRuleList（编译结果全局复用，屏广告失败不阻塞嗅探）
        if let ruleList = await ExtractionWarmUp.adBlockRuleList() {
            config.userContentController.add(ruleList)
        }

        // 规则声明的 cookie 必须在 load 之前进 store，否则首个请求带不上。
        let cookies = RuleCookies.cookies(from: rule.cookies, for: url)
        for cookie in cookies {
            await config.websiteDataStore.httpCookieStore.setCookie(cookie)
        }

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 240), configuration: config)
        let session = ExtractionSession(
            webView: webView,
            continuation: continuation,
            videoFilter: RuleVideoFilter(rule: rule)
        )
        config.userContentController.add(session, name: "cezzuVideoSink")
        webView.navigationDelegate = session

        // 把 webview 挂到 hidden host 上（系统才会真正跑 JS）
        WebViewHostingWindow.shared.attach(webView)

        var req = URLRequest(url: url)
        if !rule.referer.isEmpty {
            req.setValue(rule.referer, forHTTPHeaderField: "Referer")
        }
        if !rule.userAgent.isEmpty {
            req.setValue(rule.userAgent, forHTTPHeaderField: "User-Agent")
            webView.customUserAgent = rule.userAgent
        }
        webView.load(req)
        return session
    }

    func tearDown() async {
        guard !torn else { return }
        torn = true
        webView.stopLoading()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllContentRuleLists()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "cezzuVideoSink")
        webView.navigationDelegate = nil
        WebViewHostingWindow.shared.detach(webView)
        continuation.finish()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "cezzuVideoSink" else { return }
        guard let dict = message.body as? [String: Any] else { return }
        guard let urlString = dict["url"] as? String, let url = URL(string: urlString) else {
            return
        }
        guard let accepted = videoFilter.accept(url) else { return }
        let sourceRaw = (dict["source"] as? String) ?? ""
        let source = ExtractedMedia.Source(rawValue: sourceRaw) ?? .unknown
        let media = ExtractedMedia(url: accepted, source: source)
        continuation.yield(media)
    }
}

// MARK: - resource loading

extension WebViewVideoExtractor {
    static func loadResource(name: String, ext: String) -> String? {
        guard let url = Bundle.cezzuKit.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - hidden hosting window

@MainActor
final class WebViewHostingWindow {
    static let shared = WebViewHostingWindow()

    #if canImport(UIKit)
        private var window: UIWindow?

        func attach(_ webView: WKWebView) {
            if window == nil {
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first
                let w: UIWindow
                if let scene {
                    w = UIWindow(windowScene: scene)
                } else {
                    w = UIWindow(frame: .init(x: 0, y: 0, width: 1, height: 1))
                }
                w.isHidden = true
                w.alpha = 0
                window = w
            }
            window?.addSubview(webView)
        }

        func detach(_ webView: WKWebView) {
            webView.removeFromSuperview()
        }
    #elseif canImport(AppKit)
        private var window: NSWindow?

        func attach(_ webView: WKWebView) {
            if window == nil {
                let w = NSWindow(
                    contentRect: .init(x: -2000, y: -2000, width: 1, height: 1),
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: true
                )
                w.isReleasedWhenClosed = false
                w.alphaValue = 0
                window = w
            }
            window?.contentView?.addSubview(webView)
        }

        func detach(_ webView: WKWebView) {
            webView.removeFromSuperview()
        }
    #endif
}
