import Foundation
#if os(iOS)
import AVFoundation
#endif

/// 播放器开合系统音频会话用的抽象。`AVPlayerBackend` 只在真正起播时 `activate()`、
/// 彻底收起时 `deactivate()`；测试里换成记录器就能验证时机。
@MainActor
public protocol PlaybackAudioSessionControlling: AnyObject {
    /// 真正起播前调用。独占类别一激活，别的 App 正放着的歌就会被打断。
    func activate()
    /// 播放器彻底收起时调用，把声音交还给被打断的 App。
    func deactivate()
}

/// 真正接 `AVAudioSession` 的实现。
///
/// `.playback` 是独占类别：`setActive(true)` 的那一刻其他 App 的音频就停了。所以类别
/// 可以在启动时先设好（只设类别不抢声音），激活一定要等到真的起播 —— 放着歌点进来
/// 翻两页，音乐不该先停。收尾带 `.notifyOthersOnDeactivation`，被打断的那边
/// （Apple Music / Spotify 等）会收到通知自己续播。
///
/// macOS 没有 `AVAudioSession`，整套是空实现，调用方不用写条件编译。
@MainActor
public final class SystemPlaybackAudioSession: PlaybackAudioSessionControlling {
    public static let shared = SystemPlaybackAudioSession()

    private var isConfigured = false

    private init() {}

    /// 设类别和模式。幂等，启动时调一次即可；不会打断其他 App 的声音。
    public func configure() {
        #if os(iOS)
        guard !isConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            isConfigured = true
        } catch {
            // 留给下次 activate 再试；真失败也只是回到系统默认类别。
        }
        #endif
    }

    public func activate() {
        #if os(iOS)
        configure()
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    public func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
