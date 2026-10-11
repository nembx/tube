import Foundation

/// HLS m3u8 清单的行级解析器与改写器。把所有相对 / 绝对 URL 改写成代理路径
/// (`/p/<会话 token>/<base64url(originalAbsoluteURL)>`)，让后续切片 / 子清单 / 加密 key /
/// init segment / 备用音轨 都经过 `LocalReverseProxy`，从而带上注入的 Referer / UA。
///
/// 支持的标签：
///   - `EXTINF`            后跟切片 URI
///   - `EXT-X-STREAM-INF`  后跟子清单 URI
///   - `EXT-X-KEY URI=...`
///   - `EXT-X-MAP URI=...`
///   - `EXT-X-MEDIA URI=...`
///   - `EXT-X-I-FRAME-STREAM-INF URI=...`
///
/// 不在内部硬编码代理 host —— 由调用方提供 `proxyURLBuilder`。
public struct HLSManifestRewriter: Sendable {

    /// 把任意绝对 URL 转成本地代理 URL 的闭包。
    public typealias ProxyURLBuilder = @Sendable (URL) -> URL

    private let proxyURLBuilder: ProxyURLBuilder

    public init(proxyURLBuilder: @escaping ProxyURLBuilder) {
        self.proxyURLBuilder = proxyURLBuilder
    }

    /// 把一段 m3u8 文本改写成代理版本。`baseURL` 用于把相对 URI 解析成绝对 URI。
    public func rewrite(manifest: String, baseURL: URL) -> String {
        var output: [String] = []
        let lines = manifest.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        for raw in lines {
            let line = String(raw)
            if line.hasPrefix("#") {
                output.append(rewriteTagLine(line, baseURL: baseURL))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                output.append(line)
            } else {
                // 数据行：切片 URI 或子清单 URI
                output.append(rewriteURIData(line, baseURL: baseURL))
            }
        }
        return output.joined(separator: "\n")
    }

    // MARK: - tag rewriting

    private func rewriteTagLine(_ line: String, baseURL: URL) -> String {
        // 处理 URI="..." 子串
        if let range = line.range(of: "URI=\"") {
            let afterURI = line.index(range.upperBound, offsetBy: 0)
            if let endQuote = line[afterURI...].firstIndex(of: "\"") {
                let uriString = String(line[afterURI..<endQuote])
                if let absolute = URL(string: uriString, relativeTo: baseURL)?.absoluteURL {
                    let proxied = proxyURLBuilder(absolute).absoluteString
                    return line.replacingOccurrences(
                        of: "URI=\"\(uriString)\"",
                        with: "URI=\"\(proxied)\""
                    )
                }
            }
        }
        return line
    }

    private func rewriteURIData(_ line: String, baseURL: URL) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let absolute = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            return line
        }
        return proxyURLBuilder(absolute).absoluteString
    }
}
