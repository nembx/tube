import Foundation
import Observation
import SwiftData

/// 规则商店的高层协调器：聚合"规则源 + catalog + 已安装规则"三个状态。
///
/// 它在 MainActor 上运行（因为 SwiftData 的 ModelContext 与 SwiftUI 绑定），
/// 但所有 IO 都通过 `RemoteRuleSource` actor 与 `LocalRuleStore` actor 完成。
@MainActor
@Observable
public final class RuleStoreCoordinator {

    public enum SourceStatus: Hashable, Sendable {
        case idle
        case loading
        case ok
        case failed(message: String)
    }

    public private(set) var sources: [RuleSource] = []
    public private(set) var sourceStatus: [UUID: SourceStatus] = [:]
    public private(set) var catalog: [RuleCatalogEntry] = []
    public private(set) var installedRules: [InstalledRule] = []
    public private(set) var lastError: String?

    private let sourceStore: RuleSourceStore
    private let localStore: LocalRuleStore
    private let remote: RemoteRuleSource
    private let seedLoader: SeededRuleLoader

    public init(
        sourceStore: RuleSourceStore,
        localStore: LocalRuleStore = LocalRuleStore(),
        remote: RemoteRuleSource = RemoteRuleSource(),
        seedLoader: SeededRuleLoader = SeededRuleLoader()
    ) {
        self.sourceStore = sourceStore
        self.localStore = localStore
        self.remote = remote
        self.seedLoader = seedLoader
    }

    /// App 启动时调用一次。种子规则源、首启离线种子、与内置 SeedRules 对账，然后加载内存视图。
    public func bootstrap() async {
        do {
            try sourceStore.ensureSeedSources()
            try await seedLoader.seedIfNeeded(into: localStore)
            // 非首启也会跑：补新源、更新 version、卸掉种子里已弃用的官方规则
            try await seedLoader.reconcileOfficialSeed(into: localStore)
            try await reloadAll()
        } catch {
            lastError = "bootstrap 失败：\(error)"
        }
    }

    /// 重新从持久化层把所有内存状态填一遍（不发任何网络）。
    public func reloadAll() async throws {
        sources = try sourceStore.load()
        let persisted = try await localStore.load()
        installedRules = persisted.map {
            InstalledRule(rule: $0.rule, sourceID: $0.sourceID, isEnabled: $0.isEnabled)
        }
    }

    // MARK: - sources

    public func addCustomSource(_ source: RuleSource) async throws {
        do {
            try await remote.validateCustomSource(source)
            try sourceStore.addCustom(source)
            try await reloadAll()
            lastError = nil
        } catch {
            lastError = Self.failureMessage(action: "添加规则源 \(source.name)", error: error)
            throw error
        }
    }

    public func setSourceEnabled(id: UUID, enabled: Bool) async throws {
        try sourceStore.setEnabled(id: id, enabled: enabled)
        try await reloadAll()
    }

    public func removeCustomSource(id: UUID) async throws {
        try sourceStore.removeCustom(id: id)
        try await reloadAll()
    }

    // MARK: - catalog refresh

    public func refresh() async {
        var merged: [RuleCatalogEntry] = []
        await withTaskGroup(of: (UUID, Result<[RuleCatalogEntry], Error>).self) { group in
            for source in sources where source.isEnabled {
                sourceStatus[source.id] = .loading
                group.addTask { [remote] in
                    do {
                        let entries = try await remote.fetchIndex(source: source)
                        return (source.id, .success(entries))
                    } catch {
                        return (source.id, .failure(error))
                    }
                }
            }
            for await (sourceID, result) in group {
                switch result {
                case .success(let entries):
                    sourceStatus[sourceID] = .ok
                    merged.append(contentsOf: entries)
                case .failure(let err):
                    sourceStatus[sourceID] = .failed(message: Self.reason(for: err))
                }
            }
        }
        catalog = merged
    }

    // MARK: - rule install / update / uninstall

    public func install(name: String, fromSource sourceID: UUID) async throws {
        do {
            guard let source = sources.first(where: { $0.id == sourceID }) else {
                throw RuleEngineError.invalidURL("source \(sourceID) 不存在")
            }
            let rule = try await remote.fetchRule(name: name, source: source)
            try await localStore.install(rule: rule, sourceID: sourceID)
            try await reloadAll()
            lastError = nil
        } catch {
            lastError = Self.failureMessage(action: "安装 \(name)", error: error)
            throw error
        }
    }

    public func update(name: String) async throws {
        guard let installed = installedRules.first(where: { $0.name == name }) else {
            lastError = Self.failureMessage(action: "更新 \(name)", reason: "本地找不到这条规则")
            return
        }
        guard let sourceID = installed.sourceID else {
            lastError = Self.failureMessage(
                action: "更新 \(name)",
                reason: "这条规则没有记录来源，先卸载再从规则源重新安装"
            )
            return
        }
        try await install(name: name, fromSource: sourceID)
    }

    public func uninstall(name: String) async throws {
        do {
            try await localStore.uninstall(name: name)
            try await reloadAll()
            lastError = nil
        } catch {
            lastError = Self.failureMessage(action: "卸载 \(name)", error: error)
            throw error
        }
    }

    public func setRuleEnabled(name: String, enabled: Bool) async throws {
        try await localStore.setEnabled(name: name, enabled: enabled)
        try await reloadAll()
    }

    /// catalog 中是否有比本地更新的版本。
    public func hasUpdate(for name: String) -> Bool {
        guard let installed = installedRules.first(where: { $0.name == name }) else { return false }
        let entries = catalog.filter { $0.name == name }
        return entries.contains { $0.version != installed.version }
    }

    /// 启用搜索时使用的规则列表。
    public func enabledRules() -> [CezzuRule] {
        installedRules.filter(\.isEnabled).map(\.rule)
    }

    // MARK: - error reporting

    public func clearLastError() {
        lastError = nil
    }

    /// 把任意错误压成一句用户能看懂的原因。
    static func reason(for error: Error) -> String {
        if let ruleError = error as? RuleEngineError { return ruleError.userMessage }
        return (error as NSError).localizedDescription
    }

    static func failureMessage(action: String, error: Error) -> String {
        failureMessage(action: action, reason: reason(for: error))
    }

    static func failureMessage(action: String, reason: String) -> String {
        "\(action)失败：\(reason)"
    }
}
