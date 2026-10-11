import Foundation

/// 用户发起的跳转（拖拽结束 / ±10 秒快捷键）允许的落点偏差。
///
/// 零容差要求播放器精确落到请求的那一帧：它得回到目标点之前的关键帧、把整个 GOP
/// 解码掉再丢弃，HLS 上还要把目标点所在的分片完整拉下来。快退和拖进度条的卡顿
/// 主要来自这里 —— 容差参数存在的意义就是让播放器利用流本身的编码结构走捷径。
///
/// 取 ±2 秒与 `PlayerScrubPreviewController` 的抽帧容差一致：足够跨过常见的关键帧
/// 间隔，落点偏差在一次 10 秒跳转里也还在可接受范围内。
public enum PlayerSeekTolerance {
    public static let seconds: TimeInterval = 2
}
