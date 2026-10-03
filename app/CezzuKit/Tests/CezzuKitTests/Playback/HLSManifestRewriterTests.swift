import Foundation
import Testing
@testable import CezzuKit

@Suite("HLSManifestRewriter")
struct HLSManifestRewriterTests {

    private let proxyHost = "http://127.0.0.1:8888"
    private var rewriter: HLSManifestRewriter {
        let host = proxyHost
        return HLSManifestRewriter { url in
            let token = LocalReverseProxy.base64URL(url.absoluteString)
            return URL(string: "\(host)/p/\(token)")!
        }
    }

    @Test("media playlist with relative segment URIs")
    func mediaPlaylistRelative() {
        let manifest = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXTINF:9.967,
        seg1.ts
        #EXTINF:9.000,
        seg2.ts
        #EXT-X-ENDLIST
        """
        let baseURL = URL(string: "https://cdn.example.com/abc/index.m3u8")!
        let out = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        #expect(out.contains("\(proxyHost)/p/"))
        #expect(!out.contains("seg1.ts\n") || out.contains("\(proxyHost)/p/"))
        // 原始 URL 应该被改写
        #expect(!out.contains("\nseg1.ts"))
    }

    @Test("master playlist with absolute sub-playlist URIs")
    func masterPlaylistAbsolute() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000
        https://cdn.example.com/720p/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2560000
        https://cdn.example.com/1080p/index.m3u8
        """
        let baseURL = URL(string: "https://cdn.example.com/master.m3u8")!
        let out = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        #expect(!out.contains("https://cdn.example.com/720p/index.m3u8"))
        #expect(!out.contains("https://cdn.example.com/1080p/index.m3u8"))
        #expect(out.contains("\(proxyHost)/p/"))
    }

    @Test("EXT-X-KEY URI is rewritten")
    func extXKeyURI() {
        let manifest = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-KEY:METHOD=AES-128,URI="https://cdn.example.com/keys/k1.bin",IV=0x...
        #EXTINF:10.0,
        https://cdn.example.com/seg1.ts
        #EXT-X-ENDLIST
        """
        let baseURL = URL(string: "https://cdn.example.com/index.m3u8")!
        let out = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        #expect(!out.contains("URI=\"https://cdn.example.com/keys/k1.bin\""))
        #expect(out.contains("URI=\"\(proxyHost)/p/"))
    }

    @Test("EXT-X-MAP URI is rewritten")
    func extXMapURI() {
        let manifest = """
        #EXTM3U
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:5.0,
        seg1.m4s
        """
        let baseURL = URL(string: "https://cdn.example.com/path/index.m3u8")!
        let out = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        #expect(!out.contains("URI=\"init.mp4\""))
        #expect(out.contains("URI=\"\(proxyHost)/p/"))
    }

    @Test("base64url round-trips")
    func base64URLRoundTrip() {
        let original = "https://cdn.example.com/foo/bar.m3u8?token=abc&q=1"
        let encoded = LocalReverseProxy.base64URL(original)
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        let decoded = LocalReverseProxy.base64URLDecode(encoded)
        #expect(decoded != nil)
        let decodedString = String(data: decoded!, encoding: .utf8)
        #expect(decodedString == original)
    }
}
