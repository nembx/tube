import Foundation

/// 本地规则的 JSON 文件持久化层。单一文件 `<AppSupport>/Tube/plugins.json`，
/// 内容是 `[InstalledRulePersisted]` 数组。
public actor LocalRuleStore {

    /// 持久化用的可编码包装。把 `TubeRule` 全字段平铺，再附加 `sourceID` / `isEnabled`。
    public struct InstalledRulePersisted: Codable, Sendable {
        public var rule: TubeRule
        public var sourceID: UUID?
        public var isEnabled: Bool
    }

    private let pluginsURL: URL
    private var cache: [InstalledRulePersisted] = []
    private var loaded = false

    public init(pluginsURL: URL? = nil) {
        if let pluginsURL {
            self.pluginsURL = pluginsURL
        } else {
            self.pluginsURL = LocalRuleStore.defaultPluginsURL()
        }
    }

    public static func defaultPluginsURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Tube", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("plugins.json", isDirectory: false)
    }

    /// 是否首次运行（plugins.json 不存在）。`SeededRuleLoader` 用这个判断是否要 seed。
    public var isPristine: Bool {
        !FileManager.default.fileExists(atPath: pluginsURL.path)
    }

    public func load() throws -> [InstalledRulePersisted] {
        if loaded { return cache }
        let fm = FileManager.default
        guard fm.fileExists(atPath: pluginsURL.path) else {
            cache = []
            loaded = true
            return cache
        }
        let data = try Data(contentsOf: pluginsURL)
        if data.isEmpty {
            cache = []
        } else {
            cache = try JSONDecoder().decode([InstalledRulePersisted].self, from: data)
        }
        loaded = true
        return cache
    }

    public func save(_ items: [InstalledRulePersisted]) throws {
        cache = items
        loaded = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: pluginsURL, options: .atomic)
    }

    public func install(rule: TubeRule, sourceID: UUID?) throws {
        var items = try load()
        items.removeAll { $0.rule.name == rule.name }
        items.append(InstalledRulePersisted(rule: rule, sourceID: sourceID, isEnabled: true))
        try save(items)
    }

    public func uninstall(name: String) throws {
        var items = try load()
        items.removeAll { $0.rule.name == name }
        try save(items)
    }

    public func setEnabled(name: String, enabled: Bool) throws {
        var items = try load()
        if let idx = items.firstIndex(where: { $0.rule.name == name }) {
            items[idx].isEnabled = enabled
            try save(items)
        }
    }

    public func enabledRules() throws -> [TubeRule] {
        try load().filter(\.isEnabled).map(\.rule)
    }
}
