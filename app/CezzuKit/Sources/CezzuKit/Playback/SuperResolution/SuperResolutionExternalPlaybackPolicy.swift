import Foundation

/// 投屏时超分必须让路。
///
/// 超分不是 `.off` 时，画面由 `CAMetalLayer` 画，`AVPlayerLayer` 被隐藏
/// （见 `PlayerSurface`）。而外部播放走的正是 `AVPlayerLayer` 那条链路 ——
/// 不降回 `.off`，接收端拿到的就是一块空画面。
///
/// 只影响这一次播放的实际取值，不动用户在设置里存的偏好：退出投屏要能自己回去。
enum SuperResolutionExternalPlaybackPolicy {
    static func effectiveMode(
        preferred: SuperResolutionMode,
        isExternalPlaybackActive: Bool
    ) -> SuperResolutionMode {
        isExternalPlaybackActive ? .off : preferred
    }
}
