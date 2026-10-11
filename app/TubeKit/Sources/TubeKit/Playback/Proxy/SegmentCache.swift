import Foundation

/// 本地代理的分片缓存。
///
/// AVPlayer 只保留播放头**前方**的缓冲，往回拖必然重新请求分片 —— 没有这层缓存
/// 的话这些请求会原样打回源站。快进不痛而快退痛，差别就在这里：快进要的数据本来
/// 就没下过，快退要的数据几分钟前刚下过。
///
/// 只收完整响应（客户端没带 Range、上游回 200）。带 Range 的请求可以从完整副本里
/// 切出来，但 206 的响应自己不进缓存：手上没有全量就没法安全地服务别的区间。
struct SegmentCache {
    struct Entry: Equatable {
        let contentType: String
        let data: Data
    }

    /// 总容量。装满后按最近最少使用淘汰。
    let capacityBytes: Int
    /// 单条上限。一个超大响应不该把整个缓存挤空。
    let maximumEntryBytes: Int

    private var entries: [String: Entry] = [:]
    /// 访问顺序，末尾最新。条目数量是几百量级，线性删除足够。
    private var order: [String] = []
    private(set) var totalBytes = 0

    /// 缓存跨集存活，所以容量要按「够覆盖一次往回拖」而不是「越大越好」来定。
    /// 128 MB 在常见码率下是十分钟上下的画面，同时留住 iOS 上的内存余量。
    init(capacityBytes: Int = 128 * 1024 * 1024, maximumEntryBytes: Int = 24 * 1024 * 1024) {
        self.capacityBytes = capacityBytes
        self.maximumEntryBytes = maximumEntryBytes
    }

    /// 这个大小值不值得攒起来 —— 转发过程中提前判断，免得白占内存。
    func admits(byteCount: Int) -> Bool {
        byteCount <= maximumEntryBytes
    }

    mutating func value(for key: String) -> Entry? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry
    }

    mutating func insert(_ entry: Entry, for key: String) {
        guard admits(byteCount: entry.data.count) else { return }
        if let existing = entries[key] {
            totalBytes -= existing.data.count
            order.removeAll { $0 == key }
        }
        entries[key] = entry
        order.append(key)
        totalBytes += entry.data.count
        evictIfNeeded()
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalBytes = 0
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private mutating func evictIfNeeded() {
        while totalBytes > capacityBytes, let oldest = order.first {
            order.removeFirst()
            if let evicted = entries.removeValue(forKey: oldest) {
                totalBytes -= evicted.data.count
            }
        }
    }
}

/// `Range: bytes=…` 请求头的解析。只认单区间 —— AVPlayer 不发多区间请求。
enum HTTPByteRange {
    /// 返回落在 `[0, totalLength)` 内的闭开区间。头不合法或越界时返回 `nil`，
    /// 调用方据此退回整体响应。
    static func parse(_ header: String, totalLength: Int) -> Range<Int>? {
        guard totalLength > 0 else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }

        let startText = String(spec[..<dash])
        let endText = String(spec[spec.index(after: dash)...])

        if startText.isEmpty {
            // `bytes=-N`：最后 N 个字节。
            guard let suffix = Int(endText), suffix > 0 else { return nil }
            return max(0, totalLength - suffix)..<totalLength
        }
        guard let start = Int(startText), start >= 0, start < totalLength else { return nil }
        if endText.isEmpty { return start..<totalLength }
        guard let end = Int(endText), end >= start else { return nil }
        return start..<min(end + 1, totalLength)
    }

    static func contentRangeHeader(for range: Range<Int>, totalLength: Int) -> String {
        "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(totalLength)"
    }
}
