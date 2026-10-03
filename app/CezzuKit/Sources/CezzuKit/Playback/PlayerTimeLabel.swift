import Foundation

/// 播放页上那两个时间标签的文案。
///
/// 解析中、首帧还在缓冲的那几秒，播放器报不出总时长。这时候照常格式化会写出一行
/// `00:00 / 00:00`，看起来像一个长度为零的视频停在开头 —— 实际上只是还不知道。
/// 两边一起换成占位，把「不知道」和「零」分开。
public enum PlayerTimeLabel {
    /// 时长未知时两个标签共用的占位。
    public static let placeholder = "-:-"

    public static func hasKnownDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0
    }

    /// 已播时间。
    public static func elapsed(position: TimeInterval, duration: TimeInterval) -> String {
        guard hasKnownDuration(duration) else { return placeholder }
        return format(position)
    }

    /// 总时长。
    public static func total(_ duration: TimeInterval) -> String {
        guard hasKnownDuration(duration) else { return placeholder }
        return format(duration)
    }

    /// 剩余时间，带减号。拖过头时按 0 处理，不写出负数。
    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        guard hasKnownDuration(duration), position.isFinite else { return placeholder }
        return "-" + format(max(duration - position, 0))
    }

    /// `mm:ss`，超过一小时才补出小时那一段。
    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
