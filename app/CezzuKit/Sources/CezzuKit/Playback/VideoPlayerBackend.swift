import Foundation

/// 播放器后端的统一抽象。所有签名只依赖 Foundation 类型，方便未来接入
/// VLCKit / MPVKit 时不需要改任何 view model 代码。
///
/// 实现可以是 class 或 actor。所有方法都标记为 async 方便实现差异。
@MainActor
public protocol VideoPlayerBackend: AnyObject {
    /// 当前播放进度（秒）。
    var currentTime: TimeInterval { get }

    /// 总时长（秒，可能为 NaN）。
    var duration: TimeInterval { get }

    /// 是否正在播放。
    var isPlaying: Bool { get }

    /// 当前倍速。
    var rate: Float { get }

    /// 播放音量，0...1。是这一路播放的音量，不动系统音量。
    var volume: Float { get }

    /// 是否正把画面送到外部设备（AirPlay 等）。
    var isExternalPlaybackActive: Bool { get }

    /// 加载并准备播放一个媒体 URL。`headers` 是 best-effort 注入（AVPlayer
    /// 的 `AVURLAssetHTTPHeaderFieldsKey`，部分 CDN 不认）。
    func load(url: URL, headers: [String: String], startAt: TimeInterval) async

    func play()
    func pause()
    func seek(to seconds: TimeInterval) async
    func setRate(_ rate: Float)
    func setVolume(_ volume: Float)
    func unload()
}
