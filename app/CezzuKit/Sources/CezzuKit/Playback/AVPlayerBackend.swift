import AVFoundation
import Foundation
import Observation

/// `VideoPlayerBackend` 的默认实现 —— 直接走 `AVPlayer`。
@MainActor
@Observable
public final class AVPlayerBackend: VideoPlayerBackend {
    public let player: AVPlayer

    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    /// `true` 当 `AVPlayer` 正在等待缓冲（首帧前 / seek 后 / 中段缓冲）。
    /// 供 UI 层显示 spinner 用。
    ///
    /// 由 KVO 而不是 periodic time observer 驱动 —— 后者只在播放时钟前进时回调，
    /// 缓冲时时钟正好冻结，会错过所有该亮 spinner 的瞬间。
    public private(set) var isBuffering: Bool = false
    /// 平滑后的下行吞吐（B/s）。`nil` 表示暂无有效采样（显示「—」）。
    public private(set) var downloadSpeedBps: Double?
    /// 播放头所在那段缓冲区的结束时间（秒）。`nil` 表示尚无缓冲信息。
    public private(set) var bufferedTime: TimeInterval?
    /// 本次会话的起播耗时 / 卡顿次数 / 码率，来自 AVFoundation 自己记的 access log。
    /// 调缓冲策略和代理时用它做前后对比。
    public private(set) var diagnostics: PlaybackDiagnostics = .empty
    /// `true` 当 AVPlayer 正把画面送到外部设备（AirPlay / 有线外接屏）。
    /// 走本地反代时喂给播放器的是 `127.0.0.1`，接收端解析不到，
    /// 所以协调层要靠这个信号把地址换成局域网地址再重载。
    public private(set) var isExternalPlaybackActive: Bool = false

    /// 投屏状态翻转时回调，参数是翻转后的值。只在值真的变了时触发。
    public var onExternalPlaybackChange: ((Bool) -> Void)?

    public var rate: Float { player.rate }
    public var volume: Float { player.volume }

    private var timeObserverToken: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var externalPlaybackObservation: NSKeyValueObservation?
    private var speedSampler = DownloadSpeedSampler()
    private var speedTimer: Timer?

    /// AVPlayer 没有"正在 seek"信号，`timeControlStatus` 也不会因为 seek 翻成
    /// `.waitingToPlayAtSpecifiedRate`，所以 KVO 抓不到。由 `seek(to:)` 自己维护。
    private var isSeeking: Bool = false

    /// 起播 / 稳态两段式缓冲参数。
    public let bufferingPolicy: PlayerBufferingPolicy

    /// 当前处在哪一段。装载和跳转会把它打回起播态。
    private var bufferingStage = PlayerBufferingStageMachine()

    public init(
        player: AVPlayer = AVPlayer(),
        bufferingPolicy: PlayerBufferingPolicy = .default
    ) {
        self.player = player
        self.bufferingPolicy = bufferingPolicy
        // 缓冲不足时宁可等也不要硬播出 stall。
        player.automaticallyWaitsToMinimizeStalling = true
        installTimeObserver()
        installStateObservers()
        installSpeedTimer()
    }

    /// 调用方应该在销毁前调用此方法。`deinit` 不能访问 MainActor 状态，
    /// 所以 v1 把生命周期托管给 `PlaybackCoordinator`。
    public func dispose() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation?.invalidate()
        likelyToKeepUpObservation = nil
        externalPlaybackObservation?.invalidate()
        externalPlaybackObservation = nil
        onExternalPlaybackChange = nil
        speedTimer?.invalidate()
        speedTimer = nil
        unload()
    }

    /// periodic observer 现在只负责刷新 `currentTime` / `duration` ——
    /// 这两个需要轮询（AVPlayer 不对外暴露 KVO 流），其他状态走事件驱动。
    private func installTimeObserver() {
        let interval = CMTime(value: 1, timescale: 4)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem {
                    let total = item.duration.seconds
                    self.duration = total.isFinite ? total : 0
                }
                self.refreshBufferedTime()
            }
        }
    }

    /// 下行速度必须用墙钟定时器：播放缓冲时 AVPlayer 时钟冻结，periodic observer 不会回调。
    private func installSpeedTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDownloadSpeed()
                // 缓冲时播放时钟冻结，periodic observer 不回调，靠这个墙钟定时器补上。
                self?.refreshBufferedTime()
                self?.refreshDiagnostics()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        speedTimer = timer
    }

    private func refreshDownloadSpeed() {
        let now = ProcessInfo.processInfo.systemUptime
        if let event = player.currentItem?.accessLog()?.events.last,
           event.numberOfBytesTransferred >= 0,
           event.observedBitrate > 0
        {
            downloadSpeedBps = speedSampler.update(
                bytesTransferred: event.numberOfBytesTransferred,
                observedBitrate: event.observedBitrate,
                at: now
            )
        } else {
            downloadSpeedBps = speedSampler.currentSpeed(at: now)
        }
    }

    private func refreshDiagnostics() {
        guard let events = player.currentItem?.accessLog()?.events else { return }
        diagnostics = PlaybackDiagnosticsBuilder.make(
            from: events.map {
                PlaybackDiagnosticsBuilder.Event(
                    startupTime: $0.startupTime,
                    numberOfStalls: $0.numberOfStalls,
                    indicatedBitrate: $0.indicatedBitrate,
                    observedBitrate: $0.observedBitrate,
                    numberOfBytesTransferred: $0.numberOfBytesTransferred
                )
            }
        )
    }

    private func refreshBufferedTime() {
        guard let item = player.currentItem else {
            bufferedTime = nil
            return
        }
        let ranges = item.loadedTimeRanges.compactMap { value -> PlayerBufferedRangeResolver.Range? in
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite else { return nil }
            return PlayerBufferedRangeResolver.Range(start: start, end: end)
        }
        bufferedTime = PlayerBufferedRangeResolver.bufferedTime(
            ranges: ranges,
            currentTime: currentTime
        )
    }

    private func resetDownloadSpeed() {
        speedSampler.reset()
        downloadSpeedBps = nil
        diagnostics = .empty
    }

    /// 状态事件 KVO：`timeControlStatus` 立刻反映 .waitingToPlayAtSpecifiedRate，
    /// `currentItem` 切换时重挂 item 观察器，捕获 HLS 中段缓冲。
    private func installStateObservers() {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
        currentItemObservation = player.observe(
            \.currentItem,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.attachItemObservers()
            }
        }
        externalPlaybackObservation = player.observe(
            \.isExternalPlaybackActive,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            let active = player.isExternalPlaybackActive
            Task { @MainActor in
                self?.updateExternalPlayback(active)
            }
        }
    }

    /// KVO 回调的落点。`AVPlayer.isExternalPlaybackActive` 是只读的，
    /// 测试没法真的接一台 AirPlay 设备，所以这里留成 internal 让测试直接驱动。
    func updateExternalPlayback(_ active: Bool) {
        guard active != isExternalPlaybackActive else { return }
        isExternalPlaybackActive = active
        onExternalPlaybackChange?(active)
    }

    private func attachItemObservers() {
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation = nil

        guard let item = player.currentItem else {
            refreshPlaybackState()
            return
        }
        bufferEmptyObservation = item.observe(
            \.isPlaybackBufferEmpty,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
        likelyToKeepUpObservation = item.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
    }

    private func refreshPlaybackState() {
        let status = player.timeControlStatus
        isPlaying = status == .playing

        let waitingForRate = status == .waitingToPlayAtSpecifiedRate
        let bufferEmpty = player.currentItem?.isPlaybackBufferEmpty ?? false
        let likelyToKeepUp = player.currentItem?.isPlaybackLikelyToKeepUp ?? true
        isBuffering = isSeeking || waitingForRate || (bufferEmpty && !likelyToKeepUp)

        if bufferingStage.update(isPlaying: isPlaying, isLikelyToKeepUp: likelyToKeepUp) {
            applyBufferingStage()
        }
    }

    /// 把当前阶段的缓冲参数下发到 item。
    private func applyBufferingStage() {
        guard let item = player.currentItem else { return }
        let stage = bufferingStage.stage
        item.preferredForwardBufferDuration = bufferingPolicy.forwardBufferSeconds(at: stage)
        item.preferredPeakBitRate = bufferingPolicy.peakBitRate(at: stage)
    }

    // MARK: VideoPlayerBackend

    public func load(url: URL, headers: [String: String], startAt: TimeInterval) async {
        resetDownloadSpeed()
        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        }
        let item = AVPlayerItem(asset: asset)
        bufferingStage.restart()
        player.replaceCurrentItem(with: item)
        applyBufferingStage()
        if startAt > 0.5 {
            // 刻意不 await：等跳转完成再返回，调用方的 `play()` 就要排在整段缓冲之后，
            // 第一帧被一路推迟。这次跳转在任何数据下载之前就下发，AVPlayer 会直接从
            // 续播位置开始取流，不会先把 0 秒附近的那一批白下一遍。
            let target = CMTime(seconds: startAt, preferredTimescale: 600)
            let tolerance = CMTime(seconds: PlayerSeekTolerance.seconds, preferredTimescale: 600)
            item.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in }
        }
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to seconds: TimeInterval) async {
        isSeeking = true
        // 跳转和起播是同一件事：目标是尽快出画面，所以退回起播态的缓冲参数。
        bufferingStage.restart()
        applyBufferingStage()
        refreshPlaybackState()
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: PlayerSeekTolerance.seconds, preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
        isSeeking = false
        // seek 完成后 KVO 不一定立刻 fire（buffer 还充足时不会翻状态），
        // 主动重算一次保证 spinner 能及时收起。
        refreshPlaybackState()
    }

    public func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0), 1)
    }

    public func setRate(_ rate: Float) {
        player.rate = rate
    }

    public func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetDownloadSpeed()
        bufferedTime = nil
    }

    /// 交出一个抽当前帧的任务，作「最近观看」封面用；等不等由调用方决定。
    ///
    /// 取图管线在 HLS / 反代流上要好几秒、也可能一直不返回，所以它不能出现在关闭流程
    /// 的必经之路上 —— 挡住的话画面已经关了声音还在响。任务只抓住 asset 和时间点，
    /// 和播放器实例无关：`dispose()` 之后它照样跑得完。失败时给 `nil`，当无封面处理。
    public func detachedFrameCapture() -> Task<CGImage?, Never>? {
        guard let asset = player.currentItem?.asset else { return nil }
        let time = player.currentTime()
        guard time.isValid, time.isNumeric, !time.seconds.isNaN else { return nil }

        // 取图整段留在 main actor 之外：generator 只有它自己碰得到，
        // 也就不会把播放器那边的状态一起拖进 @concurrent 的取图管线。
        return Task.detached {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            // 放宽容差：流媒体关键帧不保证精确落在 currentTime。
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

            do {
                return try await generator.image(at: time).image
            } catch {
                return nil
            }
        }
    }
}
