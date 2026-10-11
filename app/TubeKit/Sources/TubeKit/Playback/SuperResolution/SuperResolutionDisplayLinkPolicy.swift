import QuartzCore

/// 决定超分渲染的显示链接该跑多快。
///
/// 原来显示链接是不设速率的，跟着屏幕跑 —— 120Hz 的 iPhone 上，播一部 23.976fps
/// 的番会空转 100 次 `hasNewPixelBuffer` 才等到一帧新画面，纯耗电。
///
/// 这里按片源帧率的 2 倍来定，不是 1 倍：显示时钟和视频帧到达的节拍并不对齐，
/// 卡在 1 倍上采样会周期性错过一帧、产生可见的顿挫。2 倍留够了余量。
public enum SuperResolutionDisplayLinkPolicy {
    /// 上限。再高对任何片源都没有意义，只是白烧电。
    public static let maximumFrameRate: Float = 120

    /// 下限。片源帧率再低也别把显示链接压到看起来卡的程度。
    public static let minimumFrameRate: Float = 24

    /// 片源帧率未知（刚开播、还没解出轨道信息）时返回 `nil`，
    /// 调用方保持系统默认，等帧率出来了再收敛。
    public static func preferredFrameRateRange(videoFrameRate: Float?) -> CAFrameRateRange? {
        guard let videoFrameRate, videoFrameRate > 0, videoFrameRate.isFinite else { return nil }

        let preferred = min(
            maximumFrameRate,
            max(minimumFrameRate, (videoFrameRate * 2).rounded())
        )
        return CAFrameRateRange(
            minimum: min(max(minimumFrameRate, videoFrameRate.rounded()), preferred),
            maximum: preferred,
            preferred: preferred
        )
    }
}
