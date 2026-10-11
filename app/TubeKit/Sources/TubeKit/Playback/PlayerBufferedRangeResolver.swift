import Foundation

/// 从 `AVPlayerItem.loadedTimeRanges` 里挑出「播放头所在那一段」的结束点。
///
/// seek 之后 loadedTimeRanges 会变成多个不连续区间，进度条只画播放头这一段，
/// 所以这里把多段收敛成单个 Double。抽成纯函数是为了脱离 AVFoundation 做测试。
enum PlayerBufferedRangeResolver {
    struct Range {
        let start: TimeInterval
        let end: TimeInterval
    }

    static func bufferedTime(ranges: [Range], currentTime: TimeInterval) -> TimeInterval? {
        for range in ranges where range.start <= currentTime && currentTime <= range.end {
            return range.end
        }
        return nil
    }
}
