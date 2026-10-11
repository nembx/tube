import Foundation

/// 缓冲阶段。起播和从 seek 恢复走的是同一条路径，所以共用 `.startup`。
public enum PlayerBufferingStage: Sendable, Equatable {
    /// 还没出第一帧（首次装载，或刚跳转过）。目标是尽快出画面。
    case startup
    /// 已经稳定播放。目标是别再中断。
    case steady
}

/// 起播 / 稳态两段式缓冲参数。
///
/// 一上来就要求很长的前向缓冲会把第一帧一直往后拖 —— 而且每次 seek 之后都要
/// 重来一遍。正确的做法是起播只缓够开播的量，真的播起来之后再把控制权交还给
/// AVPlayer 自己的自适应算法（`0` = 系统决定），中段缓冲交给它去避免。
public struct PlayerBufferingPolicy: Sendable, Equatable {
    /// 起播阶段的前向缓冲目标（秒）。
    public var startupForwardBufferSeconds: TimeInterval
    /// 稳态的前向缓冲目标。`0` 表示交回系统自适应。
    public var steadyForwardBufferSeconds: TimeInterval
    /// 起播阶段的码率上限（bps）。多码率清单上避免第一片就挑到最高档，
    /// 那会让首帧等上好几秒。`0` 表示不限。
    public var startupPeakBitRate: Double
    /// 稳态解除上限，网络好就让它自己往上走。
    public var steadyPeakBitRate: Double

    public init(
        startupForwardBufferSeconds: TimeInterval = 5,
        steadyForwardBufferSeconds: TimeInterval = 0,
        startupPeakBitRate: Double = 4_000_000,
        steadyPeakBitRate: Double = 0
    ) {
        self.startupForwardBufferSeconds = startupForwardBufferSeconds
        self.steadyForwardBufferSeconds = steadyForwardBufferSeconds
        self.startupPeakBitRate = startupPeakBitRate
        self.steadyPeakBitRate = steadyPeakBitRate
    }

    public static let `default` = PlayerBufferingPolicy()

    public func forwardBufferSeconds(at stage: PlayerBufferingStage) -> TimeInterval {
        switch stage {
        case .startup: startupForwardBufferSeconds
        case .steady: steadyForwardBufferSeconds
        }
    }

    public func peakBitRate(at stage: PlayerBufferingStage) -> Double {
        switch stage {
        case .startup: startupPeakBitRate
        case .steady: steadyPeakBitRate
        }
    }
}

/// 决定什么时候从起播态切到稳态。
///
/// 只有「确实在播 且 缓冲跟得上」才算稳。一旦切到稳态就不会自己退回去 ——
/// 中段缓冲是 AVPlayer 自适应算法的职责，收紧参数只会让它更难恢复；
/// 只有装载新内容或跳转才会重新进入起播态。
struct PlayerBufferingStageMachine {
    private(set) var stage: PlayerBufferingStage = .startup

    /// 装载新 item 或发起跳转。返回是否发生了变化。
    @discardableResult
    mutating func restart() -> Bool {
        guard stage != .startup else { return false }
        stage = .startup
        return true
    }

    /// 播放状态更新。返回是否发生了变化（调用方据此决定要不要重新下发参数）。
    @discardableResult
    mutating func update(isPlaying: Bool, isLikelyToKeepUp: Bool) -> Bool {
        guard stage == .startup, isPlaying, isLikelyToKeepUp else { return false }
        stage = .steady
        return true
    }
}
