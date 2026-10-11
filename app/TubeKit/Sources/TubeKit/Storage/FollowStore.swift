import Foundation
import Observation
import SwiftData

/// 追番的高层 store。持久化策略与 `HistoryStore` 一致，统一收口主线程。
@MainActor
@Observable
public final class FollowStore {
    /// 强引用 container，避免 empty→persistent 切换后 context 悬空主线程闪退。
    private let container: ModelContainer
    private let context: ModelContext

    /// 最近添加 / 更新在前，用于追番列表。
    public private(set) var items: [BangumiItem] = []

    public init(context: ModelContext) {
        self.container = context.container
        self.context = context
        try? refresh()
    }

    public func refresh() throws {
        var descriptor = FetchDescriptor<FollowEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        items = try context.fetch(descriptor).map { $0.item }
    }

    public func contains(_ item: BangumiItem) -> Bool {
        let key = FollowEntry.makeKey(for: item)
        return items.contains { FollowEntry.makeKey(for: $0) == key }
    }

    public func toggle(_ item: BangumiItem) throws {
        let key = FollowEntry.makeKey(for: item)
        let descriptor = FetchDescriptor<FollowEntry>(
            predicate: #Predicate { $0.key == key }
        )

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.insert(FollowEntry(item: item))
        }

        try context.save()
        try refresh()
    }

    /// 只加不删：已收藏则原样返回。Bangumi 同步把远端收藏并进本地时用它。
    @discardableResult
    public func insert(_ item: BangumiItem, updatedAt: Date = .now) throws -> Bool {
        let key = FollowEntry.makeKey(for: item)
        let descriptor = FetchDescriptor<FollowEntry>(
            predicate: #Predicate { $0.key == key }
        )
        guard try context.fetch(descriptor).isEmpty else { return false }
        context.insert(FollowEntry(item: item, updatedAt: updatedAt))
        try context.save()
        try refresh()
        return true
    }

    /// 批量并入远端收藏，一次 save。顺序按传入顺序，越靠前 `updatedAt` 越新。
    public func insertMissing(_ items: [BangumiItem]) throws {
        let now = Date.now
        var inserted = false
        for (offset, item) in items.enumerated() {
            let key = FollowEntry.makeKey(for: item)
            let descriptor = FetchDescriptor<FollowEntry>(
                predicate: #Predicate { $0.key == key }
            )
            guard try context.fetch(descriptor).isEmpty else { continue }
            context.insert(FollowEntry(item: item, updatedAt: now.addingTimeInterval(-Double(offset))))
            inserted = true
        }
        guard inserted else { return }
        try context.save()
        try refresh()
    }
}
