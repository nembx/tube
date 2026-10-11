import Foundation
import Testing

@testable import TubeKit

@Suite("LocalNetworkAddress 网卡优先级")
struct LocalNetworkAddressTests {

    @Test("Wi-Fi 排在其他以太网口前面")
    func prefersWiFi() {
        #expect(LocalNetworkAddress.rank(interface: "en0")
            > LocalNetworkAddress.rank(interface: "en1"))
        #expect(LocalNetworkAddress.rank(interface: "en1")
            > LocalNetworkAddress.rank(interface: "bridge100"))
    }

    @Test("蜂窝和隧道口直接排除")
    func excludesUnreachableInterfaces() {
        #expect(LocalNetworkAddress.rank(interface: "pdp_ip0") == 0)
        #expect(LocalNetworkAddress.rank(interface: "utun3") == 0)
        #expect(LocalNetworkAddress.rank(interface: "awdl0") == 0)
    }
}
