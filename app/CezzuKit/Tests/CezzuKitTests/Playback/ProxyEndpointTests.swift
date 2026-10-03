import Foundation
import Testing

@testable import CezzuKit

@Suite("ProxyEndpoint")
struct ProxyEndpointTests {

    @Test("IPv4 的 authority 就是 host:port")
    func ipv4Authority() {
        let endpoint = ProxyEndpoint(host: "192.168.1.7", port: 8080, token: "t")
        #expect(endpoint.authority == "192.168.1.7:8080")
    }

    @Test("IPv6 字面量要加方括号才是合法 authority")
    func ipv6Authority() {
        let endpoint = ProxyEndpoint(host: "fe80::1", port: 8080, token: "t")
        #expect(endpoint.authority == "[fe80::1]:8080")
        #expect(URL(string: "http://\(endpoint.authority)/p/t/x") != nil)
    }

    @Test("token 是 32 个十六进制字符且每次都不同")
    func tokenShape() {
        let a = ProxyEndpoint.makeToken()
        let b = ProxyEndpoint.makeToken()
        #expect(a.count == 32)
        #expect(a.allSatisfy { $0.isHexDigit })
        #expect(a != b)
    }

    @Test("换 host 只换 host，token 和端口不动")
    func urlCarriesTokenAndHost() {
        let original = URL(string: "https://cdn.example.com/seg.ts")!
        let loopback = ProxyEndpoint(host: "127.0.0.1", port: 8080, token: "abc")
        let lan = ProxyEndpoint(host: "192.168.1.7", port: 8080, token: "abc")

        let a = ProxySharedState.proxyURL(for: original, endpoint: loopback)
        let b = ProxySharedState.proxyURL(for: original, endpoint: lan)

        #expect(a.host == "127.0.0.1")
        #expect(b.host == "192.168.1.7")
        #expect(a.path == b.path)
        #expect(a.path.hasPrefix("/p/abc/"))
    }
}
