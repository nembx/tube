import Foundation
import Testing
@testable import TubeKit

@Suite("ProxyConnectionHandler request parsing")
struct ProxyConnectionHandlerRequestTests {

    private func head(_ text: String) -> ProxyConnectionHandler.RequestHead? {
        ProxyConnectionHandler.parseRequestHead(Data(text.utf8))
    }

    @Test("a well formed request line and its headers are read out")
    func parsesRequest() {
        let parsed = head("GET /p/abc HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-99\r\n\r\n")

        #expect(parsed?.method == "GET")
        #expect(parsed?.path == "/p/abc")
        #expect(parsed?.httpVersion == "HTTP/1.1")
        #expect(parsed?.headers["Range"] == "bytes=0-99")
    }

    @Test("a malformed request line is rejected")
    func rejectsMalformed() {
        #expect(head("GET /p/abc\r\n\r\n") == nil)
        #expect(head("\r\n\r\n") == nil)
    }

    @Test("HTTP/1.1 keeps the connection unless the client says otherwise")
    func keepAliveDefaults() {
        #expect(head("GET / HTTP/1.1\r\n\r\n")?.wantsKeepAlive == true)
        #expect(head("GET / HTTP/1.1\r\nConnection: close\r\n\r\n")?.wantsKeepAlive == false)
        // 头名大小写不敏感。
        #expect(head("GET / HTTP/1.1\r\nconnection: Close\r\n\r\n")?.wantsKeepAlive == false)
    }

    @Test("HTTP/1.0 keeps the connection only when asked to")
    func keepAliveOnHTTP10() {
        #expect(head("GET / HTTP/1.0\r\n\r\n")?.wantsKeepAlive == false)
        #expect(head("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")?.wantsKeepAlive == true)
    }

    @Test("the original URL round-trips through the proxy path")
    func decodesOriginalURL() {
        let original = URL(string: "https://cdn.example.com/a/b/seg.ts?token=x%2Fy")!
        let endpoint = ProxyEndpoint(host: "127.0.0.1", port: 9999, token: "deadbeef")
        let proxied = ProxySharedState.proxyURL(for: original, endpoint: endpoint)

        #expect(
            ProxyConnectionHandler.decodeOriginalURL(from: proxied.path, token: "deadbeef")
                == original
        )
    }

    @Test("a path that is not valid base64url decodes to nothing")
    func rejectsBadPath() {
        #expect(ProxyConnectionHandler.decodeOriginalURL(from: "/p/tok/!!!!", token: "tok") == nil)
    }

    @Test("对不上会话 token 的请求一律不解析")
    func rejectsWrongToken() {
        let original = URL(string: "https://cdn.example.com/seg.ts")!
        let endpoint = ProxyEndpoint(host: "127.0.0.1", port: 9999, token: "goodtoken")
        let proxied = ProxySharedState.proxyURL(for: original, endpoint: endpoint)

        #expect(
            ProxyConnectionHandler.decodeOriginalURL(from: proxied.path, token: "othertoken")
                == nil
        )
        // 老格式（路径里没有 token）也要挡掉。
        #expect(
            ProxyConnectionHandler.decodeOriginalURL(
                from: "/p/\(LocalReverseProxy.base64URL(original.absoluteString))",
                token: "goodtoken"
            ) == nil
        )
    }

    @Test("重写子地址时用客户端报的 Host")
    func usesClientHostForRewrite() {
        let head = self.head("GET /p/tok/abc HTTP/1.1\r\nHost: 192.168.1.7:8080\r\n\r\n")!

        #expect(ProxyConnectionHandler.authority(from: head, fallbackPort: 9999)
            == "192.168.1.7:8080")
    }

    @Test("Host 没带端口时补上代理端口")
    func appendsPortWhenHostOmitsIt() {
        let head = self.head("GET /p/tok/abc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")!

        #expect(ProxyConnectionHandler.authority(from: head, fallbackPort: 9999)
            == "127.0.0.1:9999")
    }

    @Test("带方括号的 IPv6 字面量同样要补端口")
    func appendsPortToBareIPv6Host() {
        let withPort = self.head("GET /p/tok/abc HTTP/1.1\r\nHost: [fe80::1]:8080\r\n\r\n")!
        let withoutPort = self.head("GET /p/tok/abc HTTP/1.1\r\nHost: [fe80::1]\r\n\r\n")!

        #expect(ProxyConnectionHandler.authority(from: withPort, fallbackPort: 9999)
            == "[fe80::1]:8080")
        #expect(ProxyConnectionHandler.authority(from: withoutPort, fallbackPort: 9999)
            == "[fe80::1]:9999")
    }

    @Test("客户端没报 Host 时退回回环地址")
    func fallsBackToLoopbackAuthority() {
        let head = self.head("GET /p/tok/abc HTTP/1.1\r\n\r\n")!

        #expect(ProxyConnectionHandler.authority(from: head, fallbackPort: 9999)
            == "127.0.0.1:9999")
    }
}

@Suite("ProxyConnectionHandler body collection")
struct ProxyConnectionHandlerCollectionTests {

    @Test("chunks accumulate while they stay under the limit")
    func accumulates() {
        var buffer: Data? = Data()
        ProxyConnectionHandler.collect(Data(repeating: 1, count: 40), into: &buffer, limit: 100)
        ProxyConnectionHandler.collect(Data(repeating: 2, count: 40), into: &buffer, limit: 100)

        #expect(buffer?.count == 80)
    }

    @Test("crossing the limit abandons the copy instead of holding it")
    func abandonsOversized() {
        var buffer: Data? = Data()
        ProxyConnectionHandler.collect(Data(repeating: 1, count: 80), into: &buffer, limit: 100)
        ProxyConnectionHandler.collect(Data(repeating: 2, count: 80), into: &buffer, limit: 100)

        #expect(buffer == nil)
        // 放弃之后就别再攒了，免得后面的块又把它救回来。
        ProxyConnectionHandler.collect(Data(repeating: 3, count: 1), into: &buffer, limit: 100)
        #expect(buffer == nil)
    }

    @Test("a response that was never meant to be cached stays uncollected")
    func skipsWhenDisabled() {
        var buffer: Data?
        ProxyConnectionHandler.collect(Data(repeating: 1, count: 10), into: &buffer, limit: 100)

        #expect(buffer == nil)
    }
}

@Suite("ProxyConnectionHandler HLS sniffing")
struct ProxyConnectionHandlerSniffTests {

    @Test("the content type alone is enough")
    func detectsByContentType() {
        #expect(
            ProxyConnectionHandler.isHLSResponse(
                contentType: "application/vnd.apple.mpegurl",
                data: Data()
            )
        )
    }

    @Test("a body starting with the tag is enough")
    func detectsByBody() {
        #expect(
            ProxyConnectionHandler.isHLSResponse(
                contentType: "application/octet-stream",
                data: Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)
            )
        )
    }

    @Test("a media segment is not mistaken for a manifest")
    func rejectsSegment() {
        #expect(
            !ProxyConnectionHandler.isHLSResponse(
                contentType: "video/mp2t",
                data: Data(repeating: 0x47, count: 188)
            )
        )
    }
}
