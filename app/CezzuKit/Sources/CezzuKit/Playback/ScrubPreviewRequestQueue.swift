import Foundation

/// 抽帧请求的排队规则：同一时刻只允许一张在路上，手指移动期间只保留最新的落点。
///
/// 流媒体上抽帧不是本地解码，是真的去下分片。不加约束地按固定间隔连发，请求会在
/// 网络上堆起来，跟播放本身抢带宽 —— 拖完进度条要等很久，一半是这么来的。
/// 串行化同时也是天然的节流：网络快就出得密，网络慢就自动稀疏。
struct ScrubPreviewRequestQueue {
    /// 正在生成的那张的位置。
    private(set) var inFlight: TimeInterval?
    /// 等着的最新落点。手指还在动的话它会被不断覆盖。
    private(set) var pending: TimeInterval?

    /// 记录一个新落点。返回应当立刻发起的位置；`nil` 表示先攒着，
    /// 等在路上那张回来再取最新的。
    mutating func request(at seconds: TimeInterval) -> TimeInterval? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        guard inFlight == nil else {
            pending = seconds
            return nil
        }
        inFlight = seconds
        return seconds
    }

    /// 在路上那张出完了。返回接下来该发起的位置，没有就是 `nil`。
    mutating func finish() -> TimeInterval? {
        inFlight = pending
        pending = nil
        return inFlight
    }

    mutating func reset() {
        inFlight = nil
        pending = nil
    }
}
