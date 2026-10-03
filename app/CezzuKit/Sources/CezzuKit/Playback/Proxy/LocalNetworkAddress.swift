import Darwin
import Foundation

/// 本机在局域网上的 IPv4 地址。投屏时要把代理地址里的 `127.0.0.1` 换成它 ——
/// 接收端（Mac / Apple TV）自己去拉流，回环地址在它那边指向的是它自己。
enum LocalNetworkAddress {

    /// 没有可用的局域网地址时返回 `nil`（飞行模式、只有蜂窝网等）。
    static func currentIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var best: (rank: Int, address: String)?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sockaddr = pointer.pointee.ifa_addr,
                sockaddr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let name = String(cString: pointer.pointee.ifa_name)
            let rank = self.rank(interface: name)
            guard rank > 0, best == nil || rank > best!.rank else { continue }

            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddr,
                socklen_t(sockaddr.pointee.sa_len),
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            best = (rank, String(cString: buffer))
        }
        return best?.address
    }

    /// 网卡优先级。`en0` 是 Wi-Fi，投屏的接收端几乎总在同一张 Wi-Fi 上；
    /// `pdp_ip*`（蜂窝）和 `utun*`（VPN / 隧道）上的地址接收端够不着，直接排除。
    static func rank(interface name: String) -> Int {
        if name == "en0" { return 3 }
        if name.hasPrefix("en") { return 2 }
        if name.hasPrefix("bridge") { return 1 }
        return 0
    }
}
