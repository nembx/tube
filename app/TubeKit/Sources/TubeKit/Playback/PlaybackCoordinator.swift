import Foundation
import Observation

/// 播放阶段的协调者。把"嗅探 → 决定是否走代理 → 装入 backend → 同步历史进度"
/// 这条流程串起来。
@MainActor
@Observable
public final class PlaybackCoordinator {

    public enum Phase: Hashable, Sendable {
        case idle
        case extracting
        case loading
        case playing
        case paused
        case finished
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var requiresProxyWarning: Bool = false
    public private(set) var resumePromptPositionMs: Int? = nil

    /// 实际喂给播放器的地址（走代理时就是本地代理地址）与随之注入的头。
    /// 抽帧要另开一份 asset，用的就是这两个。
    public private(set) var currentMediaURL: URL?
    public private(set) var currentMediaHeaders: [String: String] = [:]

    /// 走反代时留一份上游地址。投屏切换要拿它重新生成一个换了 host 的代理地址 ——
    /// 代理 URL 里的原始地址是 base64 过的，从代理 URL 反推回来太绕。
    private var proxiedOriginalURL: URL?

    /// 正在投屏、但这条线路投不出去（走了反代又拿不到局域网地址）。
    /// UI 据此提示，不然用户只会看到 Mac 上有声音没画面。
    public private(set) var externalPlaybackUnavailable: Bool = false

    public let backend: AVPlayerBackend
    private let extractor: WebViewVideoExtractor
    private let proxy: LocalReverseProxy
    private let history: HistoryStore?
    /// Bangumi 追番进度。匿名 / 关掉自动同步时为 nil 或内部短路。
    private let progressTracker: PlaybackProgressTracking?

    private var currentRequest: PlaybackRequest?
    private var extractionTask: Task<Void, Never>?
    private var mediaCache = ExtractedMediaCache()

    public init(
        backend: AVPlayerBackend = AVPlayerBackend(),
        extractor: WebViewVideoExtractor = WebViewVideoExtractor(),
        proxy: LocalReverseProxy = LocalReverseProxy(),
        history: HistoryStore? = nil,
        progressTracker: PlaybackProgressTracking? = nil
    ) {
        self.backend = backend
        self.extractor = extractor
        self.proxy = proxy
        self.history = history
        self.progressTracker = progressTracker
        backend.onExternalPlaybackChange = { [weak self] active in
            Task { @MainActor in
                await self?.applyExternalPlayback(active)
            }
        }
    }

    /// 投屏状态翻转时换一条地址重来。
    ///
    /// 反代监听在 `.any` 上，但喂给 AVPlayer 的地址写的是 `127.0.0.1` ——
    /// 进外部播放模式后是接收端自己去拉流，回环地址在它那边指向它自己，
    /// 于是只剩音频还从本机中继出去。换成局域网地址，头注入依然由本地代理做。
    func applyExternalPlayback(_ active: Bool) async {
        guard let original = proxiedOriginalURL else { return }

        let target: URL?
        if active {
            target = await proxy.externalPlaybackURL(for: original)
        } else {
            target = await proxy.makeProxyURL(for: original)
        }
        guard let target else {
            externalPlaybackUnavailable = true
            return
        }
        externalPlaybackUnavailable = false
        guard target != currentMediaURL else { return }

        let resumeAt = backend.currentTime
        let wasPlaying = backend.isPlaying
        currentMediaURL = target
        await backend.load(url: target, headers: currentMediaHeaders, startAt: resumeAt)
        if wasPlaying {
            backend.play()
        }
    }

    public func startPlayback(_ request: PlaybackRequest, resume: Bool) async {
        flushProgress()
        backend.unload()
        // 刻意不停代理：监听器和端口留着，AVPlayer 到本地代理的连接跨集也能接着用，
        // 缓存里上一集的分片对「上一集/下一集来回切」也还有用（超量由 LRU 淘汰）。

        currentRequest = request
        requiresProxyWarning = false
        externalPlaybackUnavailable = false

        // 同一集短时间内地址不会变，起 WKWebView 重跑一遍页面是纯浪费。
        var captured = mediaCache.value(for: request.episode.url)
        if captured == nil {
            phase = .extracting
            let stream = extractor.extract(from: request.episode.url, rule: request.rule)
            for await media in stream {
                if media.isAd { continue }
                captured = media
                break
            }
            if let media = captured {
                mediaCache.insert(media, for: request.episode.url)
            }
        }
        guard let media = captured else {
            // 提取在 15 秒内没有结果：要么资源站页面打不开（国内常见），
            // 要么页面打开了但没找到可识别的视频地址。给用户可操作的提示。
            phase = .failed(
                message: "未能从该集提取出可播放 URL。可以换一个播放源；若资源站在国内打开缓慢，"
                    + "可在设置里启用「播放代理」。"
            )
            return
        }

        phase = .loading
        let resumeMs: Int
        if resume, let positionMs = resumePromptPositionMs {
            resumeMs = positionMs
        } else {
            resumeMs = 0
        }

        let proxyEnabled = PlaybackSettings.enableLocalProxy
        let needsHeaders = request.rule.needsHeaderInjection
        let headers = makeHeaders(for: request.rule)

        let urlForPlayer: URL
        var avHeaders: [String: String] = [:]
        if needsHeaders && proxyEnabled {
            do {
                let loopbackURL = try await proxy.start(headers: headers, for: media.url)
                proxiedOriginalURL = media.url
                // 已经在投屏里换集，直接起局域网地址，省掉一次装载后再重载。
                if backend.isExternalPlaybackActive,
                    let externalURL = await proxy.externalPlaybackURL(for: media.url)
                {
                    urlForPlayer = externalURL
                } else {
                    externalPlaybackUnavailable = backend.isExternalPlaybackActive
                    urlForPlayer = loopbackURL
                }
            } catch {
                phase = .failed(message: "本地反代启动失败：\(error)")
                return
            }
        } else {
            proxiedOriginalURL = nil
            urlForPlayer = media.url
            if needsHeaders && !proxyEnabled {
                requiresProxyWarning = true
                avHeaders = headers
            }
        }

        currentMediaURL = urlForPlayer
        currentMediaHeaders = avHeaders
        await backend.load(
            url: urlForPlayer,
            headers: avHeaders,
            startAt: TimeInterval(resumeMs) / 1000.0
        )
        backend.play()
        phase = .playing

        try? history?.recordPlaybackStart(request: request)
        progressTracker?.playbackStarted(request)
    }

    public func pause() {
        backend.pause()
        phase = .paused
        flushProgress()
    }

    public func resume() {
        backend.play()
        phase = .playing
    }

    public func stop() async {
        // 必须在 dispose 前发起截帧 —— asset 得趁播放器还在的时候取出来。
        flushProgress()
        backend.dispose()
        await proxy.stop()
        extractionTask?.cancel()
        currentRequest = nil
        currentMediaURL = nil
        currentMediaHeaders = [:]
        phase = .finished
    }

    public func setRate(_ rate: Float) {
        backend.setRate(rate)
    }

    public func seek(to seconds: TimeInterval) async {
        await backend.seek(to: seconds)
    }

    public func ingestResumeHint(_ entry: WatchHistoryEntry?, for request: PlaybackRequest) {
        if let entry,
            entry.lastPositionMs > 0,
            entry.ruleName == request.rule.name,
            entry.lastEpisodeIndex == request.episodeIndex,
            entry.lastEpisodeTitle == request.episode.title
        {
            resumePromptPositionMs = entry.lastPositionMs
        } else {
            resumePromptPositionMs = nil
        }
    }

    /// 把进度写进 HistoryStore，并且顺手补一张封面。按番剧标题合并，换源不会多插一行。
    ///
    /// 进度和封面分两次写：抽帧在 HLS 源上要好几秒、也可能一直不返回，等它就等于
    /// 把关闭流程钉死在原地 —— 关闭键像是没反应，画面关了声音还在响。所以进度先落盘，
    /// 封面等抽帧自己出来了再补一次；`updateProgress` 的封面只补不抹，补写是安全的。
    private func flushProgress() {
        guard let request = currentRequest else { return }
        let positionMs = Int(backend.currentTime * 1000)
        // bgm 的「看过」只看进度，不依赖本地历史是否可用。
        progressTracker?.playbackProgressed(
            request,
            positionMs: positionMs,
            durationMs: Int(backend.duration * 1000)
        )
        guard let history else { return }
        // 进度太靠前时画面常是黑场 / 片头，跳过截帧。
        let capture = positionMs >= 1_000 ? backend.detachedFrameCapture() : nil

        try? history.updateProgress(request: request, positionMs: positionMs)

        guard let capture else { return }
        Task {
            guard let cgImage = await capture.value else { return }
            let identity = HistoryStore.identityKey(
                title: HistoryStore.bangumiTitle(for: request),
                detailURL: request.anime.detailURL.absoluteString
            )
            guard let fileURL = try? HistoryFrameCache.save(image: cgImage, identity: identity) else {
                return
            }
            try? history.updateProgress(
                request: request,
                positionMs: positionMs,
                coverURLString: fileURL.absoluteString
            )
        }
    }

    private func makeHeaders(for rule: TubeRule) -> [String: String] {
        var h: [String: String] = [:]
        if !rule.referer.isEmpty { h["Referer"] = rule.referer }
        let ua = rule.userAgent.isEmpty ? RandomUA.next() : rule.userAgent
        h["User-Agent"] = ua
        return h
    }
}
