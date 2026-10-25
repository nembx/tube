import Foundation

/// 一个"规则源"（rule source）—— 提供 `index.json` 清单 + 同名 `*.json` 规则文件
/// 的远端站点。Cezzu 支持任意数量的规则源（默认内置 tube-rule 官方 + ghfast 镜像）。
public struct RuleSource: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String  // 用户可见名 ("Tube 默认规则"、"我的私有源")
    public var indexURL: URL  // 指向 index.json
    public var ruleBaseURL: URL  // 单条规则的拉取前缀
    public var mirrorPrefix: String?  // 可选：加速镜像 ("https://ghfast.top/")
    public var isEnabled: Bool
    public var isBuiltIn: Bool  // 内置源不允许删除，只能 disable

    public init(
        id: UUID = UUID(),
        name: String,
        indexURL: URL,
        ruleBaseURL: URL,
        mirrorPrefix: String? = nil,
        isEnabled: Bool,
        isBuiltIn: Bool
    ) {
        self.id = id
        self.name = name
        self.indexURL = indexURL
        self.ruleBaseURL = ruleBaseURL
        self.mirrorPrefix = mirrorPrefix
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    // MARK: Built-ins

    /// Cezzu 官方规则源，指向 monorepo 里的 `tube-rule/`。
    public static let tubeRuleOfficial = RuleSource(
        id: UUID(uuidString: "C3220500-0001-0000-0000-000000000001")!,
        name: "Tube 默认规则",
        indexURL: URL(string: "https://raw.githubusercontent.com/nembx/tube/main/tube-rule/index.json")!,
        ruleBaseURL: URL(string: "https://raw.githubusercontent.com/nembx/tube/main/tube-rule/rules/")!,
        mirrorPrefix: nil,
        isEnabled: true,
        isBuiltIn: true
    )

    /// 默认规则源的 `ghfast.top` 镜像，默认 disabled，国内手动开。
    public static let tubeRuleGhfast = RuleSource(
        id: UUID(uuidString: "C3220500-0001-0000-0000-000000000002")!,
        name: "Tube 规则镜像 (ghfast)",
        indexURL: URL(string: "https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/tube-rule/index.json")!,
        ruleBaseURL: URL(string: "https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/tube-rule/rules/")!,
        mirrorPrefix: "https://ghfast.top/",
        isEnabled: false,
        isBuiltIn: true
    )

    /// 给定一条规则名，构造该规则在本源下的 fetch URL。
    ///
    /// 直接拼字符串而不是走相对解析：`URL(string:relativeTo:)` 会把不以 `/`
    /// 结尾的 base 的最后一段当成文件名丢掉，用户手填的自定义源经常漏这个斜杠。
    public func ruleURL(for ruleName: String) -> URL? {
        let escaped =
            ruleName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ruleName
        var base = ruleBaseURL.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: base + escaped + ".json")
    }
}
