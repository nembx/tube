import Foundation

/// 本地代理回给 AVPlayer 的 HTTP 响应头拼装。
enum ProxyResponseHead {
    /// 响应体的分帧方式 —— 决定了这条连接能不能接着用。
    ///
    /// 每个分片都新建一条 TCP 连接的代价在 HLS 上很实在：慢源上每 6~10 秒
    /// 一次握手，快退时短时间密集取片会把这笔开销放大成肉眼可见的卡顿。
    enum Framing: Equatable {
        /// 长度已知，连接可复用。
        case contentLength(Int)
        /// 长度未知但要复用连接 —— body 走 chunked 自分帧。
        case chunked
        /// 长度未知且不复用，靠关闭连接分帧。客户端明确要求 close 时才走这条。
        case close
    }

    /// 只透传播放器真正需要的头，其余（Set-Cookie、CORS 之类）一律丢弃。
    static let passthrough = ["content-type", "content-range", "accept-ranges", "etag", "last-modified"]

    static func build(
        statusCode: Int,
        upstreamHeaders: [String: String],
        framing: Framing
    ) -> String {
        var head = "HTTP/1.1 \(statusCode) OK\r\n"
        for (key, value) in upstreamHeaders.sorted(by: { $0.key < $1.key })
        where passthrough.contains(key.lowercased()) {
            head += "\(key): \(value)\r\n"
        }
        switch framing {
        case .contentLength(let length):
            head += "Content-Length: \(length)\r\n"
            head += "Connection: keep-alive\r\n"
        case .chunked:
            head += "Transfer-Encoding: chunked\r\n"
            head += "Connection: keep-alive\r\n"
        case .close:
            head += "Connection: close\r\n"
        }
        head += "\r\n"
        return head
    }
}

/// `Transfer-Encoding: chunked` 的写出端。
///
/// 上游没给 Content-Length 时唯一能既边下边发、又保住连接复用的分帧方式。
enum HTTPChunkedBody {
    static func chunk(_ payload: Data) -> Data {
        var out = Data(String(format: "%llx\r\n", UInt64(payload.count)).utf8)
        out.append(payload)
        out.append(Data("\r\n".utf8))
        return out
    }

    /// 收尾的零长度块。
    static let terminator = Data("0\r\n\r\n".utf8)
}
