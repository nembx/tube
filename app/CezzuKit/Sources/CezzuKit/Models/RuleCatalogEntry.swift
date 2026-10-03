import Foundation

/// 一条 catalog 条目（远端 `index.json` 数组里的一项）。
public struct RuleCatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var version: String
    public var useNativePlayer: Bool
    public var antiCrawlerEnabled: Bool
    public var author: String
    public var lastUpdate: Int  // epoch ms

    /// 由聚合器附加的来源标记 —— 不在 `index.json` 里。
    public var sourceID: UUID?

    /// `Identifiable`：跨源的唯一键 = `(sourceID, name)`，UI 用 `name@sourceID` 字符串。
    public var id: String {
        if let sid = sourceID { return "\(name)@\(sid.uuidString)" }
        return name
    }

    public init(
        name: String,
        version: String,
        useNativePlayer: Bool,
        antiCrawlerEnabled: Bool,
        author: String,
        lastUpdate: Int,
        sourceID: UUID? = nil
    ) {
        self.name = name
        self.version = version
        self.useNativePlayer = useNativePlayer
        self.antiCrawlerEnabled = antiCrawlerEnabled
        self.author = author
        self.lastUpdate = lastUpdate
        self.sourceID = sourceID
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case version
        case useNativePlayer
        case antiCrawlerEnabled
        case author
        case lastUpdate
        // sourceID 不参与解码 —— 仅运行时附加
    }
}

/// 已安装在本地的规则（包装 `CezzuRule` + 元数据）。
public struct InstalledRule: Hashable, Sendable, Identifiable {
    public var rule: CezzuRule
    public var sourceID: UUID?
    public var isEnabled: Bool

    public var id: String { rule.name }
    public var name: String { rule.name }
    public var version: String { rule.version }

    public init(rule: CezzuRule, sourceID: UUID?, isEnabled: Bool) {
        self.rule = rule
        self.sourceID = sourceID
        self.isEnabled = isEnabled
    }
}

extension Sequence where Element == RuleCatalogEntry {
    func excludingInstalled(_ installedRules: [InstalledRule]) -> [RuleCatalogEntry] {
        let installedNames = Set(installedRules.map(\.name))
        return filter { !installedNames.contains($0.name) }
    }
}
