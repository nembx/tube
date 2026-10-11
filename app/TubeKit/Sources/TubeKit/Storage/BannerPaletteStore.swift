import Foundation

/// 封面色板的磁盘缓存（subject id → 色板）。
///
/// 色板本身只在内存里时，每次冷启动都要重新下小图 + 重新取色，
/// 底色因此总要晚一拍才出来。取色结果对同一张封面是稳定的，值得落盘。
public final class BannerPaletteStore: @unchecked Sendable {
    /// 保留的条目上限；超出按插入顺序丢最早的，避免文件无限增长。
    public static let maxEntries: Int = 200

    private let fileURL: URL
    private let lock = NSLock()
    private var memory: [Int: CoverColorPalette]?
    /// 写入顺序，用来做淘汰。
    private var order: [Int] = []

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Tube", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("banner-palettes.json", isDirectory: false)
    }

    /// 读全部（内存命中优先）。文件缺失或损坏时返回空字典。
    public func load() -> [Int: CoverColorPalette] {
        lock.lock()
        defer { lock.unlock() }
        if let memory { return memory }
        let stored = readFromDisk()
        memory = stored
        order = Array(stored.keys)
        return stored
    }

    /// 写入一条并落盘。同 id 重复写入只更新值，不改变淘汰顺序。
    public func store(_ palette: CoverColorPalette, for id: Int) {
        lock.lock()
        defer { lock.unlock() }

        var current = memory ?? readFromDisk()
        if current[id] == nil { order.append(id) }
        current[id] = palette

        while order.count > Self.maxEntries {
            let victim = order.removeFirst()
            current[victim] = nil
        }

        memory = current
        writeToDisk(current)
    }

    // MARK: - private

    private func readFromDisk() -> [Int: CoverColorPalette] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [:] }
        // JSON 的 key 只能是字符串，落盘用 String 再转回 Int。
        guard let raw = try? JSONDecoder().decode([String: CoverColorPalette].self, from: data) else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, pair in
            if let id = Int(pair.key) { result[id] = pair.value }
        }
    }

    private func writeToDisk(_ palettes: [Int: CoverColorPalette]) {
        let raw = palettes.reduce(into: [String: CoverColorPalette]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(raw) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
