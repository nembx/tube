import Foundation
import Network

/// 一条客户端连接上的全部请求处理。
///
/// 刻意**不是** actor：收发字节的循环跑在调用它的那个 task 上，多条连接真并行，
/// 不用为了搬运一块 body 去排某个串行执行器的队。需要共享状态时才去 `state` 取。
struct ProxyConnectionHandler: Sendable {

    let state: ProxySharedState
    let relay: StreamingHTTPRelay

    /// 判定 m3u8 需要的最少字节数（`#EXTM3U` 加上可能的 BOM / 空白）。
    private static let sniffLength = 16

    /// 一条连接上可以来很多个请求 —— HLS 每个分片一个。只要客户端没说 close
    /// 就一直读下去，省掉每片一次握手。
    func run(connection: NWConnection) async {
        var carry = Data()
        while true {
            do {
                guard let raw = try await receiveRequestHead(connection: connection, carry: &carry)
                else {
                    connection.cancel()
                    return
                }
                guard let head = Self.parseRequestHead(raw) else {
                    await sendStatus(.badRequest, on: connection)
                    return
                }
                guard let originalURL = Self.decodeOriginalURL(
                    from: head.path,
                    token: state.token
                ) else {
                    await sendStatus(.notFound, on: connection)
                    return
                }
                let reusable = try await proxyToUpstream(
                    originalURL: originalURL,
                    clientHead: head,
                    connection: connection
                )
                guard reusable else {
                    connection.cancel()
                    return
                }
            } catch {
                await sendStatus(.internalServerError, on: connection)
                return
            }
        }
    }

    // MARK: - 请求解析

    struct RequestHead {
        let method: String
        let path: String
        let httpVersion: String
        let headers: [String: String]

        /// HTTP/1.1 默认复用连接，只有客户端明确说 close 才不复用。
        var wantsKeepAlive: Bool {
            let connection = (headers["Connection"] ?? headers["connection"] ?? "").lowercased()
            if connection.contains("close") { return false }
            if httpVersion.hasSuffix("1.0") { return connection.contains("keep-alive") }
            return true
        }
    }

    /// 读出下一个请求头；`carry` 留住多读的字节，供流水线上的下一个请求用。
    /// 返回 `nil` 表示对端关掉了连接。
    private func receiveRequestHead(
        connection: NWConnection,
        carry: inout Data
    ) async throws -> Data? {
        let terminator = Data([0x0d, 0x0a, 0x0d, 0x0a])
        while true {
            if let range = carry.range(of: terminator) {
                let head = Data(carry[..<range.upperBound])
                carry = Data(carry[range.upperBound...])
                return head
            }
            if carry.count > 64 * 1024 { return nil }
            let chunk = try await receive(connection: connection, max: 16 * 1024)
            if chunk.isEmpty { return nil }
            carry.append(chunk)
        }
    }

    private func receive(connection: NWConnection, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) {
                data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: data ?? Data())
                }
            }
        }
    }

    static func parseRequestHead(_ data: Data) -> RequestHead? {
        guard let text = String(data: data, encoding: .ascii) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        return RequestHead(
            method: String(parts[0]),
            path: String(parts[1]),
            httpVersion: String(parts[2]),
            headers: headers
        )
    }

    /// 路径形如 `/p/<会话 token>/<base64url(原始 URL)>`。token 对不上直接当 404 ——
    /// 监听器绑在所有网卡上，这是同网段其他人唯一够得着的一道门。
    static func decodeOriginalURL(from path: String, token: String) -> URL? {
        let prefix = "/p/\(token)/"
        guard path.hasPrefix(prefix) else { return nil }
        let stripped = String(path.dropFirst(prefix.count))
        let firstQuestion = stripped.firstIndex(of: "?") ?? stripped.endIndex
        let encoded = String(stripped[..<firstQuestion])
        guard
            let data = LocalReverseProxy.base64URLDecode(encoded),
            let raw = String(data: data, encoding: .utf8),
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    /// 客户端用哪个地址找上来，重写出去的子地址就用哪个。回环和局域网两条路各自
    /// 自洽，投屏切换时不会发出一份指向另一端的清单。
    static func authority(from head: RequestHead, fallbackPort: UInt16) -> String {
        guard let host = head.headers["Host"] ?? head.headers["host"], !host.isEmpty else {
            return "127.0.0.1:\(fallbackPort)"
        }
        // Host 里的端口可以省（默认 80），但代理跑在随机端口上，缺了就得补回去，
        // 否则重写出去的子地址全指向 80。带方括号的 IPv6 字面量也算没带端口。
        if host.hasSuffix("]") { return "\(host):\(fallbackPort)" }
        if host.contains(":") { return host }
        return "\(host):\(fallbackPort)"
    }

    // MARK: - 转发

    /// 返回这条连接还能不能接着用。
    private func proxyToUpstream(
        originalURL: URL,
        clientHead: RequestHead,
        connection: NWConnection
    ) async throws -> Bool {
        let keepAlive = clientHead.wantsKeepAlive
        let rangeHeader = clientHead.headers["Range"] ?? clientHead.headers["range"]
        let cacheKey = originalURL.absoluteString
        let authority = Self.authority(from: clientHead, fallbackPort: await state.port)
        let token = state.token

        if let cached = await state.cached(for: cacheKey) {
            return try await serveFromCache(
                cached,
                originalURL: originalURL,
                rangeHeader: rangeHeader,
                keepAlive: keepAlive,
                authority: authority,
                token: token,
                connection: connection
            )
        }

        var req = URLRequest(url: originalURL)
        req.httpMethod = clientHead.method
        for (key, value) in await state.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let rangeHeader {
            req.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        let (http, body) = try await relay.fetch(req)
        var iterator = body.makeAsyncIterator()

        // 先攒够嗅探长度：m3u8 必须整体读入才能重写 URL，媒体分片则要立刻开始转发。
        var prefix = Data()
        while prefix.count < Self.sniffLength, let chunk = try await iterator.next() {
            prefix.append(chunk)
        }

        let upstreamHeaders = Self.stringHeaders(http.allHeaderFields)
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let cacheable = Self.isCacheable(
            statusCode: http.statusCode,
            hasRangeRequest: rangeHeader != nil
        )

        if Self.isHLSResponse(contentType: contentType, data: prefix) {
            var manifest = prefix
            while let chunk = try await iterator.next() {
                manifest.append(chunk)
            }
            if cacheable {
                await state.store(
                    SegmentCache.Entry(contentType: contentType, data: manifest),
                    for: cacheKey
                )
            }
            let rewritten = Self.rewriteHLS(
                data: manifest,
                baseURL: originalURL,
                authority: authority,
                token: token
            )
            let head = ProxyResponseHead.build(
                statusCode: http.statusCode,
                upstreamHeaders: upstreamHeaders,
                framing: keepAlive ? .contentLength(rewritten.count) : .close
            )
            var out = Data(head.utf8)
            out.append(rewritten)
            if keepAlive {
                try await send(out, on: connection)
                return true
            }
            await sendAndClose(out, on: connection)
            return false
        }

        // 媒体分片：响应头先落地，body 边收边发，AVPlayer 不用等整片下完。
        let framing = Self.framing(
            expectedContentLength: http.expectedContentLength,
            keepAlive: keepAlive
        )
        let head = ProxyResponseHead.build(
            statusCode: http.statusCode,
            upstreamHeaders: upstreamHeaders,
            framing: framing
        )
        try await send(Data(head.utf8), on: connection)
        let chunked = framing == .chunked
        // 边发边攒一份副本。超出单条上限就放弃这一条，别为一个大响应占着内存。
        let limit = state.maximumCacheEntryBytes
        var collected: Data? = cacheable ? Data() : nil
        if !prefix.isEmpty {
            try await send(chunked ? HTTPChunkedBody.chunk(prefix) : prefix, on: connection)
            Self.collect(prefix, into: &collected, limit: limit)
        }
        while let chunk = try await iterator.next() {
            try await send(chunked ? HTTPChunkedBody.chunk(chunk) : chunk, on: connection)
            Self.collect(chunk, into: &collected, limit: limit)
        }
        if chunked {
            try await send(HTTPChunkedBody.terminator, on: connection)
        }
        if let collected {
            await state.store(
                SegmentCache.Entry(contentType: contentType, data: collected),
                for: cacheKey
            )
        }
        guard keepAlive else {
            connection.cancel()
            return false
        }
        return true
    }

    /// 用缓存里的完整副本回应，必要时切出请求的区间。
    private func serveFromCache(
        _ entry: SegmentCache.Entry,
        originalURL: URL,
        rangeHeader: String?,
        keepAlive: Bool,
        authority: String,
        token: String,
        connection: NWConnection
    ) async throws -> Bool {
        var status = 200
        var extraHeaders: [String: String] = ["Content-Type": entry.contentType]
        var payload = entry.data

        if Self.isHLSResponse(contentType: entry.contentType, data: entry.data) {
            // 清单存的是原始字节，重写在服务时做 —— 端口或 host 换了都不会发出过期地址。
            payload = Self.rewriteHLS(
                data: entry.data,
                baseURL: originalURL,
                authority: authority,
                token: token
            )
        } else if let rangeHeader,
            let range = HTTPByteRange.parse(rangeHeader, totalLength: entry.data.count)
        {
            status = 206
            payload = Data(entry.data[range])
            extraHeaders["Accept-Ranges"] = "bytes"
            extraHeaders["Content-Range"] = HTTPByteRange.contentRangeHeader(
                for: range,
                totalLength: entry.data.count
            )
        }

        let head = ProxyResponseHead.build(
            statusCode: status,
            upstreamHeaders: extraHeaders,
            framing: keepAlive ? .contentLength(payload.count) : .close
        )
        var out = Data(head.utf8)
        out.append(payload)
        if keepAlive {
            try await send(out, on: connection)
            return true
        }
        await sendAndClose(out, on: connection)
        return false
    }

    // MARK: - 纯函数

    static func framing(
        expectedContentLength: Int64,
        keepAlive: Bool
    ) -> ProxyResponseHead.Framing {
        if expectedContentLength >= 0 { return .contentLength(Int(expectedContentLength)) }
        return keepAlive ? .chunked : .close
    }

    /// 只有「客户端要的是整体、上游也给了整体」的响应才是完整副本，
    /// 才敢拿来服务后续的任意区间请求。
    static func isCacheable(statusCode: Int, hasRangeRequest: Bool) -> Bool {
        statusCode == 200 && !hasRangeRequest
    }

    static func collect(_ chunk: Data, into buffer: inout Data?, limit: Int) {
        guard var current = buffer else { return }
        current.append(chunk)
        buffer = current.count <= limit ? current : nil
    }

    static func stringHeaders(_ raw: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in raw {
            guard let key = key as? String, let value = value as? String else { continue }
            result[key] = value
        }
        return result
    }

    static func isHLSResponse(contentType: String, data: Data) -> Bool {
        if contentType.lowercased().contains("mpegurl") { return true }
        if data.count > 7 {
            if let prefix = String(data: data.prefix(7), encoding: .ascii),
                prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
            {
                return true
            }
        }
        return false
    }

    static func rewriteHLS(data: Data, baseURL: URL, authority: String, token: String) -> Data {
        guard let manifest = String(data: data, encoding: .utf8) else { return data }
        let rewriter = HLSManifestRewriter { url in
            ProxySharedState.proxyURL(for: url, authority: authority, token: token)
        }
        let rewritten = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        return rewritten.data(using: .utf8) ?? data
    }

    // MARK: - 写出

    enum HTTPStatus: Int {
        case badRequest = 400
        case notFound = 404
        case internalServerError = 500
    }

    private func sendStatus(_ status: HTTPStatus, on connection: NWConnection) async {
        let head = "HTTP/1.1 \(status.rawValue) ERR\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        if let data = head.data(using: .ascii) {
            await sendAndClose(data, on: connection)
        }
    }

    /// 等待本块真正写出去再返回 —— 这就是对上游的天然背压。
    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            )
        }
    }

    private func sendAndClose(_ data: Data, on connection: NWConnection) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(
                content: data,
                completion: .contentProcessed { _ in
                    connection.cancel()
                    cont.resume()
                }
            )
        }
    }
}
