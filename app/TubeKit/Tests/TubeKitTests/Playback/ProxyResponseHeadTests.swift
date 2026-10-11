import Foundation
import Testing
@testable import TubeKit

@Suite("ProxyResponseHead")
struct ProxyResponseHeadTests {

    @Test("known length is declared with Content-Length and keeps the connection")
    func withContentLength() {
        let head = ProxyResponseHead.build(
            statusCode: 200,
            upstreamHeaders: ["Content-Type": "video/mp2t"],
            framing: .contentLength(4096)
        )

        #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(head.contains("Content-Type: video/mp2t\r\n"))
        #expect(head.contains("Content-Length: 4096\r\n"))
        #expect(head.contains("Connection: keep-alive\r\n"))
        #expect(head.hasSuffix("\r\n\r\n"))
    }

    @Test("unknown length on a reusable connection falls back to chunked")
    func chunkedFraming() {
        let head = ProxyResponseHead.build(
            statusCode: 200,
            upstreamHeaders: ["Content-Type": "video/mp2t"],
            framing: .chunked
        )

        #expect(!head.contains("Content-Length"))
        #expect(head.contains("Transfer-Encoding: chunked\r\n"))
        #expect(head.contains("Connection: keep-alive\r\n"))
    }

    @Test("a client asking to close still gets close-delimited framing")
    func closeFraming() {
        let head = ProxyResponseHead.build(
            statusCode: 200,
            upstreamHeaders: ["Content-Type": "video/mp2t"],
            framing: .close
        )

        // 没有 Content-Length 时靠 Connection: close 分帧，二者缺一不可。
        #expect(!head.contains("Content-Length"))
        #expect(!head.contains("Transfer-Encoding"))
        #expect(head.contains("Connection: close"))
    }

    @Test("only playback-relevant headers are passed through")
    func filtersHeaders() {
        let head = ProxyResponseHead.build(
            statusCode: 206,
            upstreamHeaders: [
                "Content-Type": "video/mp4",
                "Content-Range": "bytes 0-99/1000",
                "Accept-Ranges": "bytes",
                "Set-Cookie": "session=secret",
                "Access-Control-Allow-Origin": "*",
            ],
            framing: .contentLength(100)
        )

        #expect(head.contains("Content-Range: bytes 0-99/1000"))
        #expect(head.contains("Accept-Ranges: bytes"))
        #expect(!head.contains("Set-Cookie"))
        #expect(!head.contains("Access-Control-Allow-Origin"))
    }

    @Test("upstream error status is relayed as-is")
    func relaysStatusCode() {
        let head = ProxyResponseHead.build(
            statusCode: 403,
            upstreamHeaders: [:],
            framing: .contentLength(0)
        )

        #expect(head.hasPrefix("HTTP/1.1 403 "))
    }

    @Test("framing prefers a known length, then reusability")
    func framingChoice() {
        #expect(
            ProxyConnectionHandler.framing(expectedContentLength: 512, keepAlive: true)
                == .contentLength(512)
        )
        #expect(
            ProxyConnectionHandler.framing(expectedContentLength: 512, keepAlive: false)
                == .contentLength(512)
        )
        #expect(ProxyConnectionHandler.framing(expectedContentLength: -1, keepAlive: true) == .chunked)
        #expect(ProxyConnectionHandler.framing(expectedContentLength: -1, keepAlive: false) == .close)
    }
}

@Suite("HTTPChunkedBody")
struct HTTPChunkedBodyTests {

    @Test("a chunk is length-prefixed in hex and CRLF-terminated")
    func encodesChunk() {
        let encoded = HTTPChunkedBody.chunk(Data(repeating: 0xAB, count: 255))

        #expect(Data(encoded.prefix(4)) == Data("ff\r\n".utf8))
        #expect(encoded.count == 4 + 255 + 2)
        #expect(Data(encoded.suffix(2)) == Data("\r\n".utf8))
    }

    @Test("an empty chunk is still well formed")
    func encodesEmptyChunk() {
        #expect(HTTPChunkedBody.chunk(Data()) == Data("0\r\n\r\n".utf8))
        #expect(HTTPChunkedBody.terminator == Data("0\r\n\r\n".utf8))
    }
}
