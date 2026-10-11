import Foundation

/// 嗅探器吐出来的一条候选媒体 URL。
public struct ExtractedMedia: Hashable, Sendable {
    public enum Source: String, Sendable, Codable {
        case xhrUrl = "xhr-url"
        case xhrCt = "xhr-ct"
        case xhrBody = "xhr-body"
        case range = "range"
        case fetchUrl = "fetch-url"
        case fetchCt = "fetch-ct"
        case fetchBody = "fetch-body"
        case fetchRange = "fetch-range"
        case tag = "tag"
        case unknown
    }

    public var url: URL
    public var source: Source

    public init(url: URL, source: Source) {
        self.url = url
        self.source = source
    }

    /// 是否疑似广告 / 不可播放（用于 caller 跳过）。
    public var isAd: Bool {
        let lower = url.absoluteString.lowercased()
        let blocked = ["googleads", "googlesyndication.com", "adtrafficquality", "doubleclick"]
        return blocked.contains { lower.contains($0) }
    }

    /// 是否是 HLS 流（用于决定是否需要 m3u8 改写）。
    public var isHLS: Bool {
        url.path.lowercased().hasSuffix(".m3u8")
    }
}
