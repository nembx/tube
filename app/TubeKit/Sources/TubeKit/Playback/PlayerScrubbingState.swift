import Foundation

struct PlayerScrubbingState {
    /// 认定「播放头已经到位」的窗口。
    ///
    /// 必须覆盖 `PlayerSeekTolerance` —— 跳转本身就允许落在目标点 ±2 秒内，
    /// 窗口比容差窄的话这个位置永远对不上，进度条会一直卡在拖拽终点。
    static let arrivalWindow: TimeInterval = PlayerSeekTolerance.seconds + 0.35

    private(set) var isActive = false
    private(set) var position: TimeInterval = 0
    private var pendingSeekPosition: TimeInterval?

    mutating func syncPlaybackTime(_ time: TimeInterval) {
        guard !isActive else { return }
        if let pendingSeekPosition {
            guard abs(time - pendingSeekPosition) <= Self.arrivalWindow else { return }
            self.pendingSeekPosition = nil
        }
        position = time
    }

    mutating func begin(at currentTime: TimeInterval) {
        guard !isActive else { return }
        isActive = true
        position = currentTime
    }

    mutating func update(position: TimeInterval) {
        self.position = position
    }

    mutating func finish() -> TimeInterval? {
        guard isActive else { return nil }
        isActive = false
        pendingSeekPosition = position
        return position
    }
}
