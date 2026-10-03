import Foundation

/// 对嗅探到的视频 URL 做规则级过滤 / 改写，对应 `CezzuRule.videoURLPattern`。
///
/// 嗅探器是"抓到什么算什么"：一个播放页常常同时冒出多路流（不同清晰度、
/// 预览片、广告垫片）。有了这个 pattern，规则就能声明"我只要长这样的那一路"。
///
/// 语义：
///   - pattern 为空 → 全放行、不改写（既有规则行为完全不变）
///   - pattern 编译失败 → 同样全放行。一条写错的正则不该让整个源播不了。
///   - pattern 有名为 `v` 的捕获组 → 用该组的内容作为真实地址
///     （站点常把真地址塞在 `?url=` 后面）
///   - 不匹配 → 丢弃
public struct RuleVideoFilter: Sendable {
    private let regex: NSRegularExpression?

    public init(pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.regex = nil
            return
        }
        self.regex = try? NSRegularExpression(pattern: trimmed, options: [])
    }

    public init(rule: CezzuRule) {
        self.init(pattern: rule.videoURLPattern)
    }

    /// 放行则返回要用的 URL（可能被 `v` 组改写过），拦下则返回 `nil`。
    public func accept(_ url: URL) -> URL? {
        guard let regex else { return url }
        let raw = url.absoluteString
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range) else {
            return nil
        }
        let captured = match.range(withName: "v")
        guard captured.location != NSNotFound, let r = Range(captured, in: raw) else {
            return url
        }
        let inner = String(raw[r])
        // `?url=` 后面的地址常常是百分号编码过的。
        let decoded = inner.removingPercentEncoding ?? inner
        return URL(string: decoded) ?? URL(string: inner) ?? url
    }
}
