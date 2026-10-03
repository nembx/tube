import Foundation

/// 嗅探结果的短时缓存。
///
/// 起一个 WKWebView、把页面连同它的 JS 跑完才能拿到播放地址，这是起播路径上最贵
/// 的一段。换集来回切、退出播放器再进来、换源失败退回上一个 —— 这些场景里同一集
/// 的地址短时间内不会变，没必要重跑一遍。
///
/// 存活时间刻意压得短：站点给的地址常带时效签名，攒久了拿回来的是过期地址。
struct ExtractedMediaCache {
    private struct Entry {
        let media: ExtractedMedia
        let storedAt: Date
    }

    let timeToLive: TimeInterval
    /// 最多记几集。超出后丢最早存进来的那条。
    let capacity: Int

    private var entries: [URL: Entry] = [:]
    private var order: [URL] = []

    init(timeToLive: TimeInterval = 300, capacity: Int = 32) {
        self.timeToLive = timeToLive
        self.capacity = capacity
    }

    mutating func value(for episodeURL: URL, now: Date = .now) -> ExtractedMedia? {
        guard let entry = entries[episodeURL] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < timeToLive else {
            remove(episodeURL)
            return nil
        }
        return entry.media
    }

    mutating func insert(_ media: ExtractedMedia, for episodeURL: URL, now: Date = .now) {
        if entries[episodeURL] != nil {
            order.removeAll { $0 == episodeURL }
        }
        entries[episodeURL] = Entry(media: media, storedAt: now)
        order.append(episodeURL)
        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    private mutating func remove(_ episodeURL: URL) {
        entries.removeValue(forKey: episodeURL)
        order.removeAll { $0 == episodeURL }
    }
}
