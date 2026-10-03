import Foundation

/// 把 `CezzuRule.cookies` 的 `"k=v; k2=v2"` 文本转成播放页要预置的 cookie。
///
/// 有些站点把清晰度、语言这类选择存在 cookie 里，播放页读 cookie 决定回哪一路流。
/// 不预置就只能拿到站点默认的那一路。
public enum RuleCookies {
    /// 解析成 `(name, value)` 序列。空片段、缺 `=`、名字为空的片段一律跳过。
    /// 值里允许出现 `=`（只按第一个 `=` 切）。
    public static func parse(_ raw: String) -> [(name: String, value: String)] {
        raw.split(separator: ";").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let sep = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[trimmed.startIndex..<sep])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let value = String(trimmed[trimmed.index(after: sep)...])
                .trimmingCharacters(in: .whitespaces)
            return (name, value)
        }
    }

    /// 生成绑定到 `url` 所在域的 `HTTPCookie`。域名取不到就返回空。
    public static func cookies(from raw: String, for url: URL) -> [HTTPCookie] {
        guard let host = url.host, !host.isEmpty else { return [] }
        return parse(raw).compactMap { pair in
            HTTPCookie(properties: [
                .name: pair.name,
                .value: pair.value,
                .domain: host,
                .path: "/",
            ])
        }
    }
}
