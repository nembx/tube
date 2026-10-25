import Foundation
import Network

/// 本地 HTTP/1.1 反向代理 —— 监听 `<random port>`，把 AVPlayer 的请求
/// 转发到原始 CDN，并在中间注入规则要求的 `Referer` / `User-Agent`。
///
/// 调用方式：
///
/// ```swift
/// let proxy = LocalReverseProxy()
/// let proxiedURL = try await proxy.start(headers: ["Referer": "..."], for: realURL)
/// // 把 proxiedURL 喂给 AVPlayer
/// // 完成播放后：
/// await proxy.stop()
/// ```
///
/// HLS 支持：当上游响应 Content-Type 是 `application/vnd.apple.mpegurl` 或 body 起头
/// `#EXTM3U` 时，会先用 `HLSManifestRewriter` 重写所有子 URI 再返回，使切片 / 子清单 /
/// 加密 key 也都经过本代理。
///
/// 这个 actor 只管监听器的生死；每条连接的收发交给 `ProxyConnectionHandler`，
/// 跑在各自的 task 上，共享状态在 `ProxySharedState` 里。
public actor LocalReverseProxy {

    private var listener: NWListener?
    private let state: ProxySharedState
    private let relay: StreamingHTTPRelay

    public init(configuration: URLSessionConfiguration? = nil) {
        self.init(configuration: configuration, cache: SegmentCache())
    }

    init(configuration: URLSessionConfiguration?, cache: SegmentCache) {
        self.state = ProxySharedState(cache: cache)
        let cfg = configuration ?? {
            let cfg = URLSessionConfiguration.ephemeral
            // 流式转发下这是「两块数据之间的空闲上限」，不是整段下载的总时长，
            // 慢源上分片下几十秒是常态，30 秒会把它们直接判死。
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 600
            // 视频 CDN 在境外时，用户可在设置里给播放链路单独配一个代理。
            PlaybackProxySettings.apply(to: cfg)
            return cfg
        }()
        self.relay = StreamingHTTPRelay(configuration: cfg)
    }

    /// 启动监听并返回一个本地代理 URL。`headers` 会被注入到所有上游请求。
    public func start(headers: [String: String], for originalURL: URL) async throws -> URL {
        await state.setHeaders(headers)
        if listener == nil {
            try await startListener()
        }
        return await state.makeProxyURL(for: originalURL)
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        await state.setPort(0)
        await state.clearCache()
    }

    /// 当前缓存占用（字节）。供测试与诊断读取。
    var cachedByteCount: Int {
        get async { await state.cachedByteCount }
    }

    /// 把任意上游 URL 转成代理 URL（回环地址，本机播放用）。
    public func makeProxyURL(for originalURL: URL) async -> URL {
        await state.makeProxyURL(for: originalURL)
    }

    /// 投屏用的代理 URL —— host 换成本机局域网地址，接收端才够得着。
    /// 没有可用局域网地址时返回 `nil`，调用方据此提示投屏不可用。
    public func externalPlaybackURL(for originalURL: URL) async -> URL? {
        guard let host = LocalNetworkAddress.currentIPv4() else { return nil }
        let endpoint = await state.endpoint(host: host)
        guard endpoint.port != 0 else { return nil }
        return ProxySharedState.proxyURL(for: originalURL, endpoint: endpoint)
    }

    // MARK: - listener

    private func startListener() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        let handler = ProxyConnectionHandler(state: state, relay: relay)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            // 每条连接一个独立 task：收发字节不再跟别的连接抢同一个串行执行器。
            Task.detached(priority: .userInitiated) {
                await handler.run(connection: connection)
            }
        }
        let portReady = AsyncStream<UInt16> { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    if let port = listener.port {
                        continuation.yield(port.rawValue)
                        continuation.finish()
                    }
                }
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        var iterator = portReady.makeAsyncIterator()
        if let p = await iterator.next() {
            await state.setPort(p)
        }
    }

    // MARK: - base64url

    static func base64URL(_ string: String) -> String {
        let data = Data(string.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ token: String) -> Data? {
        var s = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }
}
