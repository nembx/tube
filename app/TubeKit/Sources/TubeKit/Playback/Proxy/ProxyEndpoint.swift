import Foundation

/// 代理对外的落点：`host:port` 加一段会话 token。
///
/// 从前代理地址只有 `127.0.0.1:<随机端口>/p/<base64(原始URL)>`，路径不含任何秘密。
/// 监听器本来就绑在 `.any`（所有网卡）上，所以同网段的任何人扫到端口就能借这台
/// 设备当转发器。投屏要求接收端够得着这个端口，暴露面从"理论上"变成"实际上"，
/// 于是把 token 塞进路径：端口随机 + token 随机，猜中的概率可以忽略。
struct ProxyEndpoint: Sendable, Hashable {
    let host: String
    let port: UInt16
    let token: String

    /// `host:port`。IPv6 字面量要加方括号才是合法 authority。
    var authority: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// 32 个十六进制字符，够抗猜了。
    static func makeToken() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
