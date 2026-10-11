import Foundation
import Observation
import SwiftData

/// 搜索历史的协议抽象。让 ViewModel 在测试里可以注入内存 fake，
/// 不用拖 SwiftData ModelContainer。
@MainActor
public protocol SearchHistoryStoring: AnyObject {
    /// 最近一次搜索的关键字在前。
    var recent: [String] { get }

    /// 记录一次成功的搜索。空白 / 仅空格的关键字会被忽略。
    /// 同 keyword（trim 后）已存在时只更新时间戳并上浮。
    func record(keyword: String)

    /// 删除单条历史。
    func delete(keyword: String)

    /// 清空全部历史。
    func clearAll()
}

/// 搜索历史的 SwiftData 实现。
///
/// 与 `HistoryStore` / `FollowStore` 保持一致：所有操作收口主线程，
/// 因为 macOS 26 之前的 SwiftData 多线程访问有已知 bug。
@MainActor
@Observable
public final class SearchHistoryStore: SearchHistoryStoring {
    /// 历史条数上限。再多就把最旧的剔除。
    public static let maxEntries: Int = 20

    /// 必须强引用 container：`ModelContext` 不保证保住 container 的生命周期。
    /// iOS 启动会先建 empty session，再换 persistent；若 SearchViewModel 仍持有 empty 的 store，
    /// container 被释放后 `context.fetch` 会在主线程直接闪退（不是 throw）。
    private let container: ModelContainer
    private let context: ModelContext

    /// 最近搜索（按 `lastUsedAt` 倒序）。view 直接绑定这个数组渲染下拉。
    public private(set) var recent: [String] = []

    public init(context: ModelContext) {
        self.container = context.container
        self.context = context
        try? refresh()
    }

    public func refresh() throws {
        var descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.maxEntries
        recent = try context.fetch(descriptor).map(\.keyword)
    }

    public func record(keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        do {
            let descriptor = FetchDescriptor<SearchHistoryEntry>(
                predicate: #Predicate { $0.keyword == normalized }
            )
            if let existing = try context.fetch(descriptor).first {
                existing.lastUsedAt = .now
            } else {
                context.insert(SearchHistoryEntry(keyword: normalized))
            }
            try context.save()
            try pruneOverflow()
            try refresh()
        } catch {
            // 记录失败不影响主流程：用户搜索仍然完成，只是没存上历史。
        }
    }

    public func delete(keyword: String) {
        let target = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        do {
            let descriptor = FetchDescriptor<SearchHistoryEntry>(
                predicate: #Predicate { $0.keyword == target }
            )
            if let existing = try context.fetch(descriptor).first {
                context.delete(existing)
                try context.save()
                try refresh()
            }
        } catch {
            // 删除失败时静默：UI 层下次刷新自然恢复一致。
        }
    }

    public func clearAll() {
        do {
            try context.delete(model: SearchHistoryEntry.self)
            try context.save()
            try refresh()
        } catch {
            // 清空失败时静默。
        }
    }

    /// 超过上限时把最旧的剔除。每次 record 后调用。
    private func pruneOverflow() throws {
        var descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.maxEntries + 32
        let all = try context.fetch(descriptor)
        guard all.count > Self.maxEntries else { return }
        for stale in all[Self.maxEntries..<all.count] {
            context.delete(stale)
        }
        try context.save()
    }
}

/// 内存版 fake，用于测试 / 预览。线程语义与 protocol 一致（MainActor）。
@MainActor
public final class InMemorySearchHistoryStore: SearchHistoryStoring {
    public private(set) var recent: [String] = []
    private let limit: Int

    public init(limit: Int = SearchHistoryStore.maxEntries, seed: [String] = []) {
        self.limit = limit
        self.recent = Array(seed.prefix(limit))
    }

    public func record(keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        recent.removeAll { $0 == normalized }
        recent.insert(normalized, at: 0)
        if recent.count > limit {
            recent.removeLast(recent.count - limit)
        }
    }

    public func delete(keyword: String) {
        recent.removeAll { $0 == keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public func clearAll() {
        recent.removeAll()
    }
}
