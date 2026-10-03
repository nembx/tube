import Foundation
import SwiftData

/// SwiftData 持久化的规则源记录。
@Model
public final class RuleSourceRecord {
    public var id: UUID
    public var name: String
    public var indexURLString: String
    public var ruleBaseURLString: String
    public var mirrorPrefix: String?
    public var isEnabled: Bool
    public var isBuiltIn: Bool
    public var addedAt: Date

    public init(
        id: UUID,
        name: String,
        indexURLString: String,
        ruleBaseURLString: String,
        mirrorPrefix: String?,
        isEnabled: Bool,
        isBuiltIn: Bool,
        addedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.indexURLString = indexURLString
        self.ruleBaseURLString = ruleBaseURLString
        self.mirrorPrefix = mirrorPrefix
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.addedAt = addedAt
    }

    public func toRuleSource() -> RuleSource? {
        guard
            let indexURL = URL(string: indexURLString),
            let ruleBaseURL = URL(string: ruleBaseURLString)
        else { return nil }
        return RuleSource(
            id: id,
            name: name,
            indexURL: indexURL,
            ruleBaseURL: ruleBaseURL,
            mirrorPrefix: mirrorPrefix,
            isEnabled: isEnabled,
            isBuiltIn: isBuiltIn
        )
    }
}

/// 规则源的高层 store —— 在 MainActor 上跑（SwiftData ModelContext 不是 Sendable）。
@MainActor
public final class RuleSourceStore {
    /// 强引用 container，避免 empty→persistent 切换后 context 悬空主线程闪退。
    private let container: ModelContainer
    private let context: ModelContext

    public init(context: ModelContext) {
        self.container = context.container
        self.context = context
    }

    /// 启动时调用。按固定 ID 补齐并迁移内置源，保留用户的启用状态。
    public func ensureSeedSources() throws {
        let allDescriptor = FetchDescriptor<RuleSourceRecord>()
        let existing = try context.fetch(allDescriptor)

        Self.reconcileSeedSources(existing: existing) { source in
            let record = RuleSourceRecord(
                id: source.id,
                name: source.name,
                indexURLString: source.indexURL.absoluteString,
                ruleBaseURLString: source.ruleBaseURL.absoluteString,
                mirrorPrefix: source.mirrorPrefix,
                isEnabled: source.isEnabled,
                isBuiltIn: source.isBuiltIn
            )
            context.insert(record)
        }
        try context.save()
    }

    static func reconcileSeedSources(existing: [RuleSourceRecord], insert: (RuleSource) -> Void) {
        let seeds = [RuleSource.cezzuRuleOfficial, RuleSource.cezzuRuleGhfast]
        for source in seeds {
            if let record = existing.first(where: { $0.id == source.id }) {
                record.name = source.name
                record.indexURLString = source.indexURL.absoluteString
                record.ruleBaseURLString = source.ruleBaseURL.absoluteString
                record.mirrorPrefix = source.mirrorPrefix
                record.isBuiltIn = source.isBuiltIn
                continue
            }

            insert(source)
        }
    }

    public func load() throws -> [RuleSource] {
        let descriptor = FetchDescriptor<RuleSourceRecord>(
            sortBy: [SortDescriptor(\.addedAt)]
        )
        let records = try context.fetch(descriptor)
        // built-in 排在自定义之前
        let builtIn = records.filter { $0.isBuiltIn }
        let custom = records.filter { !$0.isBuiltIn }
        return (builtIn + custom).compactMap { $0.toRuleSource() }
    }

    public func addCustom(_ source: RuleSource) throws {
        precondition(!source.isBuiltIn, "addCustom 不接受 built-in 源；它们由 ensureSeedSources 种子")
        let record = RuleSourceRecord(
            id: source.id,
            name: source.name,
            indexURLString: source.indexURL.absoluteString,
            ruleBaseURLString: source.ruleBaseURL.absoluteString,
            mirrorPrefix: source.mirrorPrefix,
            isEnabled: source.isEnabled,
            isBuiltIn: false
        )
        context.insert(record)
        try context.save()
    }

    public func setEnabled(id: UUID, enabled: Bool) throws {
        let descriptor = FetchDescriptor<RuleSourceRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try context.fetch(descriptor).first {
            record.isEnabled = enabled
            try context.save()
        }
    }

    public func removeCustom(id: UUID) throws {
        let descriptor = FetchDescriptor<RuleSourceRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try context.fetch(descriptor).first, !record.isBuiltIn {
            context.delete(record)
            try context.save()
        }
    }
}
