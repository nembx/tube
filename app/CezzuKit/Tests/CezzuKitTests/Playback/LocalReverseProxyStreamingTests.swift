import Foundation
import Network
import Testing
@testable import CezzuKit

/// 假上游：按预设分块把 body 逐块喂给 URLSession，模拟慢源的分片下发。
private final class StubUpstream: URLProtocol, @unchecked Sendable {
    struct Stub {
        let contentType: String
        let chunks: [Data]
        /// 是否让上游声明 Content-Length —— 决定了代理走定长还是 chunked 分帧。
        var declaresLength: Bool = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stub: Stub?

    static func install(_ stub: Stub) {
        lock.withLock { Self.stub = stub }
    }

    static func reset() {
        lock.withLock {
            Self.stub = nil
            Self.requestCount = 0
        }
    }

    /// 实际打到上游的请求数 —— 缓存有没有生效就看它。
    nonisolated(unsafe) private static var requestCount = 0

    static var upstreamRequests: Int {
        lock.withLock { Self.requestCount }
    }

    private static var current: Stub? {
        lock.withLock { Self.stub }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requestCount += 1 }
        guard let stub = Self.current, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var fields = ["Content-Type": stub.contentType]
        if stub.declaresLength {
            fields["Content-Length"] = String(stub.chunks.reduce(0) { $0 + $1.count })
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: fields
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("LocalReverseProxy streaming", .serialized)
struct LocalReverseProxyStreamingTests {

    private func makeProxy() -> LocalReverseProxy {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubUpstream.self]
        return LocalReverseProxy(configuration: config)
    }

    private func waitForCache(_ proxy: LocalReverseProxy, byteCount: Int) async throws {
        // The final socket write can reach the client before the server task commits its cache.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await proxy.cachedByteCount != byteCount, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let actual = await proxy.cachedByteCount
        try #require(actual == byteCount)
    }

    /// 直接开 socket 说 HTTP，绕开 URLSession 对本地明文连接的限制。
    private func rawGET(_ url: URL) async throws -> Data {
        let host = NWEndpoint.Host(url.host ?? "127.0.0.1")
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))!
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global())
        defer { connection.cancel() }

        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(request.utf8),
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }

        var received = Data()
        while true {
            let (chunk, isComplete) = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<(Data, Bool), Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: (data ?? Data(), isComplete))
                    }
                }
            }
            received.append(chunk)
            if isComplete || chunk.isEmpty { break }
        }
        return received
    }

    private func splitResponse(_ raw: Data) -> (head: String, body: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = raw.range(of: separator) else {
            return (String(decoding: raw, as: UTF8.self), Data())
        }
        return (
            String(decoding: raw[..<range.lowerBound], as: UTF8.self),
            Data(raw[range.upperBound...])
        )
    }

    @Test("media segment bytes arrive intact across chunk boundaries")
    func streamsMediaSegment() async throws {
        let chunks = [
            Data(repeating: 0xA1, count: 1024),
            Data(repeating: 0xB2, count: 2048),
            Data(repeating: 0xC3, count: 512),
        ]
        StubUpstream.install(.init(contentType: "video/mp2t", chunks: chunks))
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg.ts")!
        )
        let (head, body) = splitResponse(try await rawGET(proxied))
        await proxy.stop()

        #expect(head.contains("Content-Type: video/mp2t"))
        #expect(body == chunks.reduce(Data(), +))
    }

    @Test("manifest is buffered whole and its segment URLs rewritten to the proxy")
    func rewritesManifest() async throws {
        let manifest = """
            #EXTM3U
            #EXT-X-TARGETDURATION:10
            #EXTINF:10.0,
            seg1.ts
            #EXT-X-ENDLIST
            """
        StubUpstream.install(
            .init(contentType: "application/vnd.apple.mpegurl", chunks: [Data(manifest.utf8)])
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/live/index.m3u8")!
        )
        let connection = try openConnection(to: proxied)
        defer { connection.cancel() }
        var buffer = Data()
        try await sendRequest(path: pathAndQuery(proxied), on: connection)
        let (head, body) = try await readResponse(on: connection, buffer: &buffer)
        await proxy.stop()

        let text = String(decoding: body, as: UTF8.self)
        // 重写过的清单长度已知，必须给出 Content-Length 才能保住连接复用。
        #expect(head.contains("Content-Length:"))
        #expect(head.contains("Connection: keep-alive"))
        #expect(text.hasPrefix("#EXTM3U"))
        #expect(text.contains("http://127.0.0.1:"))
        #expect(!text.contains("\nseg1.ts"))
    }

    // MARK: - keep-alive 客户端

    private func openConnection(to url: URL) throws -> NWConnection {
        let host = NWEndpoint.Host(url.host ?? "127.0.0.1")
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))!
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global())
        return connection
    }

    private func pathAndQuery(_ url: URL) -> String {
        url.path + (url.query.map { "?\($0)" } ?? "")
    }

    private func sendRequest(
        path: String,
        headers: [String: String] = [:],
        on connection: NWConnection
    ) async throws {
        var request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            request += "\(key): \(value)\r\n"
        }
        request += "\r\n"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(request.utf8),
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }
    }

    private func receiveMore(into buffer: inout Data, on connection: NWConnection) async throws {
        let chunk = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: data ?? Data()) }
            }
        }
        if chunk.isEmpty { throw URLError(.networkConnectionLost) }
        buffer.append(chunk)
    }

    /// 按响应头声明的分帧方式读完一个响应，连接保持打开。
    private func readResponse(
        on connection: NWConnection,
        buffer: inout Data
    ) async throws -> (head: String, body: Data) {
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            try await receiveMore(into: &buffer, on: connection)
        }
        let range = buffer.range(of: separator)!
        let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
        buffer = Data(buffer[range.upperBound...])

        if let length = contentLength(in: head) {
            while buffer.count < length {
                try await receiveMore(into: &buffer, on: connection)
            }
            let body = Data(buffer.prefix(length))
            buffer = Data(buffer.dropFirst(length))
            return (head, body)
        }
        guard head.contains("Transfer-Encoding: chunked") else {
            return (head, buffer)
        }
        return (head, try await readChunkedBody(on: connection, buffer: &buffer))
    }

    private func contentLength(in head: String) -> Int? {
        for line in head.components(separatedBy: "\r\n")
        where line.lowercased().hasPrefix("content-length:") {
            return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func readChunkedBody(
        on connection: NWConnection,
        buffer: inout Data
    ) async throws -> Data {
        let crlf = Data("\r\n".utf8)
        var body = Data()
        while true {
            while buffer.range(of: crlf) == nil {
                try await receiveMore(into: &buffer, on: connection)
            }
            let lineEnd = buffer.range(of: crlf)!
            let sizeText = String(decoding: buffer[..<lineEnd.lowerBound], as: UTF8.self)
            guard let size = Int(sizeText, radix: 16) else {
                throw URLError(.cannotParseResponse)
            }
            buffer = Data(buffer[lineEnd.upperBound...])
            while buffer.count < size + 2 {
                try await receiveMore(into: &buffer, on: connection)
            }
            body.append(buffer.prefix(size))
            buffer = Data(buffer.dropFirst(size + 2))
            if size == 0 { return body }
        }
    }

    @Test("an unknown-length segment streams as chunked and keeps the connection")
    func streamsChunkedSegment() async throws {
        let chunks = [
            Data(repeating: 0x11, count: 900),
            Data(repeating: 0x22, count: 1300),
        ]
        StubUpstream.install(.init(contentType: "video/mp2t", chunks: chunks))
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg.ts")!
        )
        let connection = try openConnection(to: proxied)
        defer { connection.cancel() }
        var buffer = Data()
        try await sendRequest(path: pathAndQuery(proxied), on: connection)
        let (head, body) = try await readResponse(on: connection, buffer: &buffer)
        await proxy.stop()

        #expect(head.contains("Transfer-Encoding: chunked"))
        #expect(head.contains("Connection: keep-alive"))
        #expect(body == chunks.reduce(Data(), +))
    }

    @Test("two segment requests are served over one connection")
    func reusesConnection() async throws {
        let payload = Data(repeating: 0x5A, count: 4096)
        StubUpstream.install(
            .init(contentType: "video/mp2t", chunks: [payload], declaresLength: true)
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let first = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg1.ts")!
        )
        let second = await proxy.makeProxyURL(for: URL(string: "https://upstream.test/seg2.ts")!)

        let connection = try openConnection(to: first)
        defer { connection.cancel() }
        var buffer = Data()

        try await sendRequest(path: pathAndQuery(first), on: connection)
        let (firstHead, firstBody) = try await readResponse(on: connection, buffer: &buffer)
        // 同一条连接上接着发第二个请求 —— 复用不成立的话这里会读不到东西。
        try await sendRequest(path: pathAndQuery(second), on: connection)
        let (secondHead, secondBody) = try await readResponse(on: connection, buffer: &buffer)
        await proxy.stop()

        #expect(firstHead.contains("Content-Length: 4096"))
        #expect(secondHead.contains("Content-Length: 4096"))
        #expect(firstBody == payload)
        #expect(secondBody == payload)
    }

    @Test("a repeated segment is served from cache instead of the origin")
    func servesRepeatedSegmentFromCache() async throws {
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        StubUpstream.install(
            .init(contentType: "video/mp2t", chunks: [payload], declaresLength: true)
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg.ts")!
        )
        let connection = try openConnection(to: proxied)
        defer { connection.cancel() }
        var buffer = Data()
        let path = pathAndQuery(proxied)

        try await sendRequest(path: path, on: connection)
        let (_, first) = try await readResponse(on: connection, buffer: &buffer)
        // 快退回到刚看过的地方：同一个分片再要一次，不该再打到源站。
        try await sendRequest(path: path, on: connection)
        let (secondHead, second) = try await readResponse(on: connection, buffer: &buffer)

        #expect(first == payload)
        #expect(second == payload)
        #expect(secondHead.contains("Content-Length: 4096"))
        #expect(StubUpstream.upstreamRequests == 1)
        await proxy.stop()
    }

    @Test("a range request is sliced out of the cached whole body")
    func servesRangeFromCache() async throws {
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        StubUpstream.install(
            .init(contentType: "video/mp4", chunks: [payload], declaresLength: true)
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/movie.mp4")!
        )
        let connection = try openConnection(to: proxied)
        defer { connection.cancel() }
        var buffer = Data()
        let path = pathAndQuery(proxied)

        try await sendRequest(path: path, on: connection)
        _ = try await readResponse(on: connection, buffer: &buffer)
        try await sendRequest(path: path, headers: ["Range": "bytes=100-199"], on: connection)
        let (head, body) = try await readResponse(on: connection, buffer: &buffer)

        #expect(head.hasPrefix("HTTP/1.1 206 "))
        #expect(head.contains("Content-Range: bytes 100-199/4096"))
        #expect(body == Data(payload[100..<200]))
        #expect(StubUpstream.upstreamRequests == 1)
        await proxy.stop()
    }

    @Test("stopping the proxy drops what it cached")
    func stopClearsCache() async throws {
        let payload = Data(repeating: 0x7F, count: 2048)
        StubUpstream.install(
            .init(contentType: "video/mp2t", chunks: [payload], declaresLength: true)
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg.ts")!
        )
        let connection = try openConnection(to: proxied)
        var buffer = Data()
        try await sendRequest(path: pathAndQuery(proxied), on: connection)
        _ = try await readResponse(on: connection, buffer: &buffer)
        try await waitForCache(proxy, byteCount: payload.count)
        connection.cancel()

        #expect(await proxy.cachedByteCount == 2048)
        await proxy.stop()
        #expect(await proxy.cachedByteCount == 0)
    }

    @Test("switching episodes keeps the same listener and its cache")
    func startIsReusableAcrossEpisodes() async throws {
        let payload = Data(repeating: 0x3C, count: 1024)
        StubUpstream.install(
            .init(contentType: "video/mp2t", chunks: [payload], declaresLength: true)
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let first = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/ep1/seg.ts")!
        )
        let connection = try openConnection(to: first)
        defer { connection.cancel() }
        var buffer = Data()
        try await sendRequest(path: pathAndQuery(first), on: connection)
        _ = try await readResponse(on: connection, buffer: &buffer)

        // 换集只是换个上游地址，监听端口和缓存都该留着 ——
        // 端口变了 AVPlayer 到本地代理的连接就要全部重建。
        let second = try await proxy.start(
            headers: ["Referer": "https://upstream.test/"],
            for: URL(string: "https://upstream.test/ep2/seg.ts")!
        )
        #expect(second.port == first.port)
        try await waitForCache(proxy, byteCount: payload.count)
        #expect(await proxy.cachedByteCount == 1024)
        await proxy.stop()
    }

    @Test("a body shorter than the sniff window still round-trips")
    func handlesTinyBody() async throws {
        let tiny = Data("ok".utf8)
        StubUpstream.install(.init(contentType: "application/octet-stream", chunks: [tiny]))
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/tiny.bin")!
        )
        let (_, body) = splitResponse(try await rawGET(proxied))
        await proxy.stop()

        #expect(body == tiny)
    }
}
