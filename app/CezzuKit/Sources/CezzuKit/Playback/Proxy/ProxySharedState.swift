import Foundation

/// 代理的共享可变状态：注入头、监听端口、分片缓存。
///
/// 单独成一个 actor，是为了把转发数据的那条路径从它身上摘下来 —— 从前每一块 body
/// 都要跨一次 actor 边界，高码率下这是实打实的吞吐上限。现在一次请求只碰它三下：
/// 取注入头、查缓存、写缓存；中间收发字节的循环完全不经过它。
actor ProxySharedState {
    private(set) var headers: [String: String] = [:]
    private(set) var port: UInt16 = 0
    private var cache: SegmentCache

    /// 本次进程内固定的会话 token，作为代理路径的第一段。见 `ProxyEndpoint`。
    nonisolated let token: String = ProxyEndpoint.makeToken()

    /// 单条缓存上限。转发过程中要频繁判断，做成不可变量传给调用方，
    /// 免得为了问一个常数每块数据都跨一次边界。
    nonisolated let maximumCacheEntryBytes: Int

    init(cache: SegmentCache) {
        self.cache = cache
        self.maximumCacheEntryBytes = cache.maximumEntryBytes
    }

    func setHeaders(_ headers: [String: String]) {
        self.headers = headers
    }

    func setPort(_ port: UInt16) {
        self.port = port
    }

    var cachedByteCount: Int { cache.totalBytes }

    func cached(for key: String) -> SegmentCache.Entry? {
        cache.value(for: key)
    }

    func store(_ entry: SegmentCache.Entry, for key: String) {
        cache.insert(entry, for: key)
    }

    func clearCache() {
        cache.removeAll()
    }

    /// 把任意上游 URL 转成本地代理 URL（回环地址）。
    func makeProxyURL(for originalURL: URL) -> URL {
        Self.proxyURL(for: originalURL, endpoint: endpoint(host: "127.0.0.1"))
    }

    /// 换一个 host 的同一个落点。投屏时要用局域网地址，接收端解析不到回环地址。
    func endpoint(host: String) -> ProxyEndpoint {
        ProxyEndpoint(host: host, port: port, token: token)
    }

    nonisolated static func proxyURL(for originalURL: URL, endpoint: ProxyEndpoint) -> URL {
        proxyURL(for: originalURL, authority: endpoint.authority, token: endpoint.token)
    }

    /// 转发过程中重写 HLS 子地址走这条 —— 那里手上只有客户端报的 authority。
    nonisolated static func proxyURL(
        for originalURL: URL,
        authority: String,
        token: String
    ) -> URL {
        let encoded = LocalReverseProxy.base64URL(originalURL.absoluteString)
        return URL(string: "http://\(authority)/p/\(token)/\(encoded)")!
    }
}
