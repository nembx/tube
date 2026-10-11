import Foundation

/// 一次播放会话的关键指标，来自 `AVPlayerItem` 的 access log。
///
/// 改缓冲策略、改代理这类事情，光靠"感觉快了"没法判断。这几个数是 AVFoundation
/// 自己记的账，可以拿来做改动前后的对比。
public struct PlaybackDiagnostics: Sendable, Equatable {
    /// 从打开到第一帧的耗时（秒）。`nil` 表示还没出画面或系统没记。
    public var startupSeconds: TimeInterval?
    /// 整段会话累计的卡顿次数。
    public var stallCount: Int
    /// 当前选中变体的标称码率（bps）。`nil` 表示未知（例如单码率或渐进式）。
    public var indicatedBitrate: Double?
    /// 观测到的实际下行吞吐（bps）。
    public var observedBitrate: Double?
    /// 累计下行字节。
    public var transferredBytes: Int64

    public static let empty = PlaybackDiagnostics(
        startupSeconds: nil,
        stallCount: 0,
        indicatedBitrate: nil,
        observedBitrate: nil,
        transferredBytes: 0
    )
}

/// 把一串 access log 事件归并成一份指标。
///
/// 拆成纯函数是因为 `AVPlayerItemAccessLogEvent` 造不出来 —— 只能由系统产出。
/// 归并规则本身可以单独验证。
enum PlaybackDiagnosticsBuilder {

    /// access log 事件里用得上的那几个字段。系统用负值 / NaN 表示"没有这个数"。
    struct Event {
        var startupTime: TimeInterval
        var numberOfStalls: Int
        var indicatedBitrate: Double
        var observedBitrate: Double
        var numberOfBytesTransferred: Int64
    }

    static func make(from events: [Event]) -> PlaybackDiagnostics {
        var result = PlaybackDiagnostics.empty
        for event in events {
            // 起播耗时只记在会话开头那条上，后面的事件不会重复给。
            if result.startupSeconds == nil, event.startupTime.isFinite, event.startupTime >= 0 {
                result.startupSeconds = event.startupTime
            }
            if event.numberOfStalls > 0 {
                result.stallCount += event.numberOfStalls
            }
            if event.numberOfBytesTransferred > 0 {
                result.transferredBytes += event.numberOfBytesTransferred
            }
            // 码率取最后一条有效的：它反映的是"现在在放哪一档"。
            if event.indicatedBitrate.isFinite, event.indicatedBitrate > 0 {
                result.indicatedBitrate = event.indicatedBitrate
            }
            if event.observedBitrate.isFinite, event.observedBitrate > 0 {
                result.observedBitrate = event.observedBitrate
            }
        }
        return result
    }
}
