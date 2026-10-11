import Foundation
@preconcurrency import WebKit

/// 嗅探会话的公共预热资源。
///
/// 起播路径上有两笔跟内容无关的固定开销，过去每次播放都要重付一遍：
///   1. `compileContentRuleList` 每次都落盘编译一遍广告规则表；
///   2. 每个新 `WKWebView` 都要拉起一个 web content 进程。
///
/// 这里把两笔都提前付掉，并在进程内留住结果。（`WKProcessPool` 从 macOS 12 起
/// 已是空操作，进程复用只能靠留住一个活着的 WKWebView 让 WebKit 的进程缓存生效。）
@MainActor
enum ExtractionWarmUp {

    private static var ruleList: WKContentRuleList?
    private static var ruleListTask: Task<WKContentRuleList?, Never>?
    private static var warmWebView: WKWebView?

    /// 编译好的广告屏蔽规则表。系统的 store 本身会持久化编译结果，
    /// 所以这里先 lookUp，拿不到才编译；进程内再留一份，换集不用再问。
    static func adBlockRuleList() async -> WKContentRuleList? {
        if let ruleList { return ruleList }
        if let ruleListTask { return await ruleListTask.value }

        let task = Task { () -> WKContentRuleList? in
            guard let store = WKContentRuleListStore.default() else { return nil }
            let identifier = "tube-adblock"
            let existing = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                    continuation.resume(returning: list)
                }
            }
            if let existing { return existing }
            return try? await store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: AdBlockRules.jsonSource
            )
        }
        ruleListTask = task
        let result = await task.value
        ruleList = result
        ruleListTask = nil
        return result
    }

    /// 提前把上面两笔开销付掉。进详情页时调一次，等用户点下播放就已经就绪。
    /// 重复调用是安全的。
    static func prewarm() {
        if warmWebView == nil {
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: config)
            // 留着不放，web content 进程就一直活着，后续会话直接挂上去。
            webView.loadHTMLString("<html></html>", baseURL: nil)
            warmWebView = webView
        }
        Task { _ = await adBlockRuleList() }
    }
}
