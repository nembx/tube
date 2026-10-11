import Foundation
import Observation
import SwiftData

/// 观看历史的高层 store。所有 SwiftData 操作都在 MainActor 上 —— Apple 在 macOS 26
/// 之前的 SwiftData 多线程访问有 bug，统一收口主线程是 v1 最稳的做法。
///
/// **身份键**：同一番剧只保留一条记录。换源 / 换线路只更新该条的 `detailURL` /
/// `ruleName`，不再按源站 URL 各插一条（否则「最近观看」会出现一连串同名第 1 集）。
///
/// **生命周期**：必须强引用 `ModelContainer`。`ModelContext` 不保证保住 container；
/// iOS 启动 empty → persistent 切换时，若 store 仍指着已被释放的 container，
/// `context.fetch` 会在主线程直接闪退（不是 throw）—— 与 SearchHistoryStore 同因。
@MainActor
@Observable
public final class HistoryStore {
    /// 强引用，防止 context 悬空。见类型注释。
    private let container: ModelContainer
    private let context: ModelContext

    /// 最近观看（按 `updatedAt` 倒序），用于 Sidebar / TabView 的"最近"页。
    public private(set) var recent: [WatchHistoryEntry] = []

    public init(context: ModelContext) {
        self.container = context.container
        self.context = context
        // 启动只做只读 fetch；去重放到 `refresh(deduplicating:)`，避免 init 阶段
        // delete+save 踩 SwiftData 启动时序 / unique 约束 trap。
        try? loadRecent()
    }

    public func refresh() throws {
        try refresh(deduplicating: true)
    }

    public func refresh(deduplicating: Bool) throws {
        if deduplicating {
            try deduplicateByBangumiIdentity()
        }
        try loadRecent()
    }

    private func loadRecent() throws {
        var descriptor = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        recent = try context.fetch(descriptor)
    }

    /// 在用户启动播放时调用，新建或更新条目。
    ///
    /// 以番剧标题为身份（空标题回退 detailURL）。同一标题下的旧源记录会被合并删除。
    public func recordPlaybackStart(
        request: PlaybackRequest,
        coverURL: URL? = nil
    ) throws {
        let bangumiTitle = Self.bangumiTitle(for: request)
        let detailKey = request.anime.detailURL.absoluteString
        let episode = request.episode
        let resolvedCoverURL = coverURL ?? URL(string: request.item?.images.best ?? "")

        let candidates = try fetchCandidates(title: bangumiTitle, detailURL: detailKey)
        let keeper = pickKeeper(from: candidates)

        for entry in candidates where entry.persistentModelID != keeper?.persistentModelID {
            context.delete(entry)
        }

        if let existing = keeper {
            // 换源前：先清掉仍占用目标 detailURL 的其它行，避免 unique 约束 trap。
            try deleteOthers(withDetailURL: detailKey, keeping: existing)
            existing.detailURLString = detailKey
            existing.bangumiTitle = bangumiTitle.isEmpty ? existing.bangumiTitle : bangumiTitle
            existing.lastEpisodeIndex = episode.index
            existing.lastEpisodeTitle = episode.title
            existing.ruleName = request.anime.ruleName
            // 已有当前帧封面时不要被番剧海报盖掉。
            if !Self.isLocalFrameCover(existing.coverURLString) {
                existing.coverURLString = resolvedCoverURL?.absoluteString ?? existing.coverURLString
            }
            existing.lastPositionMs = 0
            existing.subjectID = Self.subjectID(for: request) ?? existing.subjectID
            existing.updatedAt = .now
        } else {
            try deleteOthers(withDetailURL: detailKey, keeping: nil)
            let entry = WatchHistoryEntry(
                detailURLString: detailKey,
                bangumiTitle: bangumiTitle,
                coverURLString: resolvedCoverURL?.absoluteString,
                ruleName: request.anime.ruleName,
                lastEpisodeIndex: episode.index,
                lastEpisodeTitle: episode.title,
                lastPositionMs: 0,
                subjectID: Self.subjectID(for: request)
            )
            context.insert(entry)
        }
        try context.save()
        try loadRecent()
    }

    /// 进度更新。播放暂停 / 退出时由 `PlaybackCoordinator.flushProgress` 调用。
    /// `coverURLString` 可为本地帧文件路径（`file://`）。
    public func updateProgress(
        request: PlaybackRequest,
        positionMs: Int,
        coverURLString: String? = nil
    ) throws {
        let bangumiTitle = Self.bangumiTitle(for: request)
        let detailKey = request.anime.detailURL.absoluteString
        let candidates = try fetchCandidates(title: bangumiTitle, detailURL: detailKey)
        let entry = pickKeeper(from: candidates)

        if let entry {
            for extra in candidates where extra.persistentModelID != entry.persistentModelID {
                context.delete(extra)
            }
            try deleteOthers(withDetailURL: detailKey, keeping: entry)
            entry.detailURLString = detailKey
            entry.bangumiTitle = bangumiTitle.isEmpty ? entry.bangumiTitle : bangumiTitle
            entry.lastEpisodeIndex = request.episode.index
            entry.lastEpisodeTitle = request.episode.title
            entry.ruleName = request.anime.ruleName
            entry.lastPositionMs = max(0, positionMs)
            // 条目号只补不抹：合成条目（id 0）不能把已经存下的真号冲掉。
            entry.subjectID = Self.subjectID(for: request) ?? entry.subjectID
            if let coverURLString, !coverURLString.isEmpty {
                entry.coverURLString = coverURLString
            }
            entry.updatedAt = .now
            try context.save()
            try loadRecent()
            return
        }

        try deleteOthers(withDetailURL: detailKey, keeping: nil)
        let created = WatchHistoryEntry(
            detailURLString: detailKey,
            bangumiTitle: bangumiTitle,
            coverURLString: coverURLString,
            ruleName: request.anime.ruleName,
            lastEpisodeIndex: request.episode.index,
            lastEpisodeTitle: request.episode.title,
            lastPositionMs: max(0, positionMs),
            subjectID: Self.subjectID(for: request)
        )
        context.insert(created)
        try context.save()
        try loadRecent()
    }

    /// 兼容旧调用方：仅按 detailURL 写进度（不改封面 / 不合并标题）。
    public func updateProgress(detailURL: URL, positionMs: Int) throws {
        let key = detailURL.absoluteString
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == key }
        )
        if let entry = try context.fetch(descriptor).first {
            entry.lastPositionMs = max(0, positionMs)
            entry.updatedAt = .now
            try context.save()
            try loadRecent()
        }
    }

    /// 首页「继续观看」预览条数。
    nonisolated public static let continueWatchingLimit: Int = 20

    /// 首页继续观看列表（最近在前，最多 `continueWatchingLimit` 条）。
    public var continueWatching: [WatchHistoryEntry] {
        Array(recent.prefix(Self.continueWatchingLimit))
    }

    public func delete(_ entry: WatchHistoryEntry) throws {
        context.delete(entry)
        try context.save()
        try loadRecent()
    }

    public func clearAll() throws {
        try context.delete(model: WatchHistoryEntry.self)
        try context.save()
        try loadRecent()
    }

    /// 给定一个详情页 URL，看是否有历史 resume 点。
    public func entry(forDetailURL url: URL) throws -> WatchHistoryEntry? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == key }
        )
        return try context.fetch(descriptor).first
    }

    public func entry(forBangumiItem item: BangumiItem) throws -> WatchHistoryEntry? {
        let title = item.displayName
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.bangumiTitle == title }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Identity / dedupe

    /// 同一番剧的稳定身份：优先标题，空标题回退 detailURL。
    nonisolated public static func identityKey(title: String, detailURL: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? detailURL : trimmed
    }

    nonisolated public static func bangumiTitle(for request: PlaybackRequest) -> String {
        let fromItem = request.item?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromItem.isEmpty { return fromItem }
        return request.anime.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 播放请求携带的 bangumi 条目号。从「继续观看」进来的请求带的是合成条目（id 0），
    /// 这种情况返回 nil，让调用方保留已经存下的号。
    nonisolated public static func subjectID(for request: PlaybackRequest) -> Int? {
        guard let id = request.item?.id, id > 0 else { return nil }
        return id
    }

    nonisolated public static func isLocalFrameCover(_ coverURLString: String?) -> Bool {
        guard let coverURLString, let url = URL(string: coverURLString) else { return false }
        return url.isFileURL
    }

    private func fetchCandidates(title: String, detailURL: String) throws -> [WatchHistoryEntry] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let descriptor = FetchDescriptor<WatchHistoryEntry>(
                predicate: #Predicate { $0.detailURLString == detailURL }
            )
            return try context.fetch(descriptor)
        }
        // 分两次 fetch，避免复杂 OR Predicate 在部分 SwiftData 版本上出问题。
        let byTitle = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.bangumiTitle == trimmed }
        )
        let byDetail = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == detailURL }
        )
        let titleHits = try context.fetch(byTitle)
        let detailHits = try context.fetch(byDetail)
        var merged: [WatchHistoryEntry] = []
        var seen = Set<PersistentIdentifier>()
        for entry in titleHits + detailHits {
            if seen.insert(entry.persistentModelID).inserted {
                merged.append(entry)
            }
        }
        return merged
    }

    private func pickKeeper(from candidates: [WatchHistoryEntry]) -> WatchHistoryEntry? {
        candidates.max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// 删除占用同一 `detailURLString` 的其它行（`@Attribute(.unique)` 冲突会直接 trap）。
    private func deleteOthers(
        withDetailURL detailURL: String,
        keeping keeper: WatchHistoryEntry?
    ) throws {
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == detailURL }
        )
        for entry in try context.fetch(descriptor) {
            if let keeper, entry.persistentModelID == keeper.persistentModelID {
                continue
            }
            context.delete(entry)
        }
    }

    /// 清掉历史脏数据：同标题只留最新一条。不修改 detailURL，避免 unique 冲突。
    private func deduplicateByBangumiIdentity() throws {
        let all = try context.fetch(FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        var seen: [String: WatchHistoryEntry] = [:]
        var dirty = false
        for entry in all {
            let key = Self.identityKey(title: entry.bangumiTitle, detailURL: entry.detailURLString)
            if seen[key] != nil {
                context.delete(entry)
                dirty = true
            } else {
                seen[key] = entry
            }
        }
        if dirty {
            try context.save()
        }
    }
}
