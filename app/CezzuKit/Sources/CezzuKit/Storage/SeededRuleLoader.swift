import Foundation

/// 离线种子加载器：把 SwiftPM resources 里的 `SeedRules/` 同步进本地 `plugins.json`。
///
/// - 首启（`plugins.json` 不存在）：整表写入
/// - 之后每次 bootstrap：与种子对账 —— 补齐新增、按 version 更新、移除已弃用的官方种子规则
public struct SeededRuleLoader: Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle.cezzuKit
    }

    /// 从 SwiftPM resources 读所有种子规则文件并解码，**自动跳过 `deprecated: true` 的规则**。
    public func loadSeedRules() throws -> [CezzuRule] {
        guard let seedURL = bundle.url(forResource: "SeedRules", withExtension: nil) else {
            return []
        }
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: seedURL, includingPropertiesForKeys: nil)
        var rules: [CezzuRule] = []
        let decoder = JSONDecoder()
        for entry in entries
        where entry.pathExtension == "json" && entry.lastPathComponent != "index.json" {
            do {
                let data = try Data(contentsOf: entry)
                // 先用 JSONSerialization 检查 deprecated 字段（CezzuRule 不解码这个字段）
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    (object["deprecated"] as? Bool) == true
                {
                    continue
                }
                let rule = try decoder.decode(CezzuRule.self, from: data)
                rules.append(rule)
            } catch {
                // 单个种子文件失败不阻塞整体 —— 跳过即可
                continue
            }
        }
        return rules
    }

    /// 从 SwiftPM resources 读种子 catalog（`index.json`）。
    public func loadSeedCatalog() throws -> [RuleCatalogEntry] {
        guard let url = bundle.url(forResource: "SeedRules/index", withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([RuleCatalogEntry].self, from: data)
    }

    /// 把种子规则一次性灌进 LocalRuleStore。仅在 `localStore.isPristine == true` 时调用。
    public func seedIfNeeded(into localStore: LocalRuleStore) async throws {
        let pristine = await localStore.isPristine
        guard pristine else { return }
        let rules = try loadSeedRules()
        let officialID = RuleSource.cezzuRuleOfficial.id
        let payload = rules.map {
            LocalRuleStore.InstalledRulePersisted(
                rule: $0,
                sourceID: officialID,
                isEnabled: true
            )
        }
        try await localStore.save(payload)
    }

    /// 将本地已安装的**官方种子规则**与当前 App 内置 `SeedRules/` 对账。
    ///
    /// - 种子里有、本地没有 → 安装（默认启用）
    /// - 两边都有但 `version` 不同 → 用种子覆盖，保留用户的 `isEnabled`
    /// - 本地有、种子已弃用/移除，且 `sourceID` 是官方或 `nil`（首启种子）→ 卸载
    /// - 其它源安装的规则不动
    public func reconcileOfficialSeed(into localStore: LocalRuleStore) async throws {
        let seedRules = try loadSeedRules()
        guard !seedRules.isEmpty else { return }

        let officialID = RuleSource.cezzuRuleOfficial.id
        let seedByName = Dictionary(uniqueKeysWithValues: seedRules.map { ($0.name, $0) })
        let seedNames = Set(seedByName.keys)

        var items = try await localStore.load()
        var changed = false

        // 1) 移除已不在种子 active 集里的官方规则（例如 LMM / yishijie）
        let beforeCount = items.count
        items.removeAll { item in
            let fromOfficial = item.sourceID == nil || item.sourceID == officialID
            return fromOfficial && !seedNames.contains(item.rule.name)
        }
        if items.count != beforeCount { changed = true }

        // 2) 补齐 / 更新种子规则
        for (name, seed) in seedByName {
            if let idx = items.firstIndex(where: { $0.rule.name == name }) {
                let existing = items[idx]
                if existing.rule.version != seed.version {
                    items[idx] = LocalRuleStore.InstalledRulePersisted(
                        rule: seed,
                        sourceID: officialID,
                        isEnabled: existing.isEnabled
                    )
                    changed = true
                }
            } else {
                items.append(
                    LocalRuleStore.InstalledRulePersisted(
                        rule: seed,
                        sourceID: officialID,
                        isEnabled: true
                    )
                )
                changed = true
            }
        }

        if changed {
            try await localStore.save(items)
        }
    }
}
