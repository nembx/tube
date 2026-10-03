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
}
