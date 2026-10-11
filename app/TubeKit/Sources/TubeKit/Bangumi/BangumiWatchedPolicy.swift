import Foundation

/// 「这一集算不算看完了」的判定。纯函数，方便单测。
///
/// 与 animeko 的 `MarkAsWatchedExtension` 同一条规则：进度过了
/// `min(时长 × 90%, 时长 − 100s)` 就算看完 —— 片尾 ED 很多人直接跳，不要求播到 100%；
/// 短片用减 100 秒那条兜底，免得 3 分钟的片要看到最后几秒。时长不足 10 秒的不判。
public enum BangumiWatchedPolicy {
    public static let ratioThreshold: Double = 0.9
    public static let tailMs: Int = 100_000
    public static let minimumDurationMs: Int = 10_000

    public static func isWatched(positionMs: Int, durationMs: Int) -> Bool {
        guard durationMs >= minimumDurationMs, positionMs > 0 else { return false }
        let byRatio = Int(Double(durationMs) * ratioThreshold)
        let byTail = durationMs - tailMs
        return positionMs >= min(byRatio, byTail)
    }
}
