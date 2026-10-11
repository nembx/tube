import Foundation
import Observation

/// 播放进度的观察者。`PlaybackCoordinator` 在开播 / 暂停 / 停止 / 换集时回调，
/// 由 `BangumiCollectionStore` 把它翻译成 bgm 上的「在看」和「看过第 N 集」。
@MainActor
public protocol PlaybackProgressTracking: AnyObject {
    func playbackStarted(_ request: PlaybackRequest)
    func playbackProgressed(_ request: PlaybackRequest, positionMs: Int, durationMs: Int)
}

/// 远端收藏并入本地追番页时需要的最小能力。`FollowStore` 实现它；
/// 单测用假对象，绕开 SwiftData 在 CLI 下跑不起来的问题。
@MainActor
public protocol FollowMirroring: AnyObject {
    @discardableResult
    func insert(_ item: BangumiItem, updatedAt: Date) throws -> Bool
    func insertMissing(_ items: [BangumiItem]) throws
}

extension FollowStore: FollowMirroring {}

/// Bangumi 追番数据的同步层：收藏状态（想看 / 在看 / 看过 …）和单集观看记录。
///
/// **数据流向**：bgm 是权威。登录后 `syncAll` 把远端收藏拉下来并入本地 `FollowStore`
/// （只加不删，匿名时期的本地收藏保留）；用户在详情页改状态、播放器里看完一集，
/// 都先改本地再推远端，失败回滚并记 `lastError`。
///
/// **缓存**：收藏列表落一份 JSON 到 Application Support，冷启动先显示上次的，
/// 再后台刷新。单集状态按条目懒加载，不落盘。
@MainActor
@Observable
public final class BangumiCollectionStore: PlaybackProgressTracking {
    /// subjectID → 收藏。
    public private(set) var collections: [Int: BangumiUserCollection] = [:]
    /// subjectID → (episodeID → 状态)。只有打开过详情页 / 播过的条目才有。
    public private(set) var episodeStates: [Int: [Int: BangumiEpisodeCollectionType]] = [:]
    /// subjectID → bgm 正片列表。和 `episodeStates` 一起加载。
    public private(set) var episodeLists: [Int: [BangumiEpisode]] = [:]
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var lastError: String?

    public static let autoTrackKey = "tube.bangumi.autoTrackPlayback"
    public static let autoTrackDefault = true

    private let auth: BangumiAuthStore
    private let api: BangumiAccountAPIProtocol
    private let subjectAPI: BangumiAPIClientProtocol
    private let followStore: FollowMirroring
    private let defaults: UserDefaults
    private let cacheFileURL: URL
    private var episodeLoadTasks: [Int: Task<Void, Never>] = [:]
    /// 一次播放只标记一次看完 —— pause / stop / 换集都会回调进度，不能每次都打接口。
    private var markedWatched: Set<String> = []
    private var lastSyncedUserID: Int?

    public init(
        auth: BangumiAuthStore,
        followStore: FollowMirroring,
        api: BangumiAccountAPIProtocol = BangumiAPIClient.shared,
        subjectAPI: BangumiAPIClientProtocol = BangumiAPIClient.shared,
        defaults: UserDefaults = .standard,
        cacheFileURL: URL? = nil
    ) {
        self.auth = auth
        self.followStore = followStore
        self.api = api
        self.subjectAPI = subjectAPI
        self.defaults = defaults
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL()
        restoreCache()
    }

    // MARK: - Settings

    /// 播放时自动同步进度到 bgm。关掉后只保留手动改状态。
    public var autoTrackPlayback: Bool {
        get { defaults.object(forKey: Self.autoTrackKey) as? Bool ?? Self.autoTrackDefault }
        set { defaults.set(newValue, forKey: Self.autoTrackKey) }
    }

    public var isLoggedIn: Bool { auth.isLoggedIn }

    // MARK: - Queries

    public func collection(for subjectID: Int) -> BangumiUserCollection? {
        collections[subjectID]
    }

    public func collectionType(for item: BangumiItem) -> BangumiCollectionType? {
        guard item.id > 0 else { return nil }
        return collections[item.id]?.type
    }

    public func episodeState(subjectID: Int, episodeID: Int) -> BangumiEpisodeCollectionType {
        episodeStates[subjectID]?[episodeID] ?? .none
    }

    /// 已看集数（done 的数量）。
    public func watchedCount(subjectID: Int) -> Int {
        episodeStates[subjectID]?.values.filter(\.isWatched).count ?? 0
    }

    /// 播放器里的第 N 集（0 起）对应的 bgm 单集。列表没加载就是 nil。
    public func bangumiEpisode(subjectID: Int, episodeIndex: Int) -> BangumiEpisode? {
        guard let list = episodeLists[subjectID] else { return nil }
        return BangumiEpisode.match(episodeIndex: episodeIndex, in: list)
    }

    /// 播放器里的第 N 集（0 起）在 bgm 上是否已标记看过。
    public func isEpisodeWatched(subjectID: Int, episodeIndex: Int) -> Bool {
        guard let episode = bangumiEpisode(subjectID: subjectID, episodeIndex: episodeIndex) else {
            return false
        }
        return episodeState(subjectID: subjectID, episodeID: episode.id).isWatched
    }

    /// 详情页里手动切换某一集的看过 / 未看。
    public func toggleEpisodeWatched(subjectID: Int, episodeIndex: Int, item: BangumiItem?) async {
        await loadEpisodeStates(subjectID: subjectID)
        guard let episode = bangumiEpisode(subjectID: subjectID, episodeIndex: episodeIndex) else { return }
        let watched = episodeState(subjectID: subjectID, episodeID: episode.id).isWatched
        await setEpisodeState(watched ? .none : .done, subjectID: subjectID, episode: episode, item: item)
    }

    /// 按 bgm 分类分组的本地收藏。没在 bgm 收藏过的条目归到 nil。
    public func items(ofType type: BangumiCollectionType?, in items: [BangumiItem]) -> [BangumiItem] {
        items.filter { collectionType(for: $0) == type }
    }

    public func count(ofType type: BangumiCollectionType) -> Int {
        collections.values.filter { $0.type == type }.count
    }

    // MARK: - Sync

    /// 登录后拉全量收藏。翻页直到拿完；中途失败保留已拿到的部分。
    public func syncAll() async {
        guard auth.isLoggedIn else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let token = try await auth.validAccessToken()
            // `/v0/users/{username}/collections` 需要用户名；刚登录可能还没拉到资料。
            if auth.user == nil { await auth.refreshUser() }
            guard let username = auth.user?.username, !username.isEmpty else {
                throw BangumiAuthError.notLoggedIn
            }

            var fetched: [BangumiUserCollection] = []
            var offset = 0
            let pageSize = 50
            while true {
                let page = try await api.collections(
                    username: username,
                    type: nil,
                    limit: pageSize,
                    offset: offset,
                    token: token
                )
                fetched.append(contentsOf: page.items)
                guard page.hasMore, !page.items.isEmpty else { break }
                offset = page.nextOffset
                // 防御：bgm 返回的 total 偶尔比实际多，不让它死循环。
                if offset > 5_000 { break }
            }

            var next: [Int: BangumiUserCollection] = [:]
            for collection in fetched where collection.subjectID > 0 {
                next[collection.subjectID] = collection
            }
            collections = next
            lastSyncedAt = .now
            lastSyncedUserID = auth.user?.id
            lastError = nil
            persistCache()

            // 远端收藏并入本地追番页。列表接口按更新时间倒序，保持这个顺序。
            let subjects = fetched.compactMap(\.subject)
            try? followStore.insertMissing(subjects)
        } catch {
            handle(error)
        }
    }

    /// 登出时清空内存和缓存。本地 `FollowStore` 不动。
    public func clear() {
        collections = [:]
        episodeStates = [:]
        episodeLists = [:]
        markedWatched = []
        lastSyncedAt = nil
        lastSyncedUserID = nil
        lastError = nil
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    // MARK: - Subject collection

    /// 改收藏状态。先改本地（UI 立即响应），再推 bgm，失败回滚。
    public func setCollection(_ type: BangumiCollectionType, for item: BangumiItem) async {
        guard item.id > 0, auth.isLoggedIn else { return }
        let subjectID = item.id
        let previous = collections[subjectID]
        let optimistic = BangumiUserCollection(
            subjectID: subjectID,
            type: type,
            epStatus: previous?.epStatus ?? 0,
            volStatus: previous?.volStatus ?? 0,
            rate: previous?.rate ?? 0,
            comment: previous?.comment ?? "",
            isPrivate: previous?.isPrivate ?? false,
            tags: previous?.tags ?? [],
            updatedAt: ISO8601DateFormatter().string(from: .now),
            subject: previous?.subject ?? item
        )
        collections[subjectID] = optimistic
        try? followStore.insert(item, updatedAt: .now)

        do {
            let token = try await auth.validAccessToken()
            try await api.updateSubjectCollection(
                subjectID: subjectID,
                update: BangumiCollectionUpdate(type: type),
                token: token
            )
            lastError = nil
            persistCache()
        } catch {
            collections[subjectID] = previous
            handle(error)
        }
    }

    // MARK: - Episode collection

    /// 加载条目的正片列表与单集状态。已加载过就不重复打接口。
    public func loadEpisodeStates(subjectID: Int, force: Bool = false) async {
        guard subjectID > 0, auth.isLoggedIn else { return }
        if !force, episodeStates[subjectID] != nil { return }
        if let running = episodeLoadTasks[subjectID] {
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchEpisodeStates(subjectID: subjectID)
        }
        episodeLoadTasks[subjectID] = task
        await task.value
        episodeLoadTasks[subjectID] = nil
    }

    private func fetchEpisodeStates(subjectID: Int) async {
        do {
            let token = try await auth.validAccessToken()
            async let episodes = subjectAPI.fetchEpisodes(subjectID: subjectID)
            async let states = api.episodeCollections(subjectID: subjectID, token: token)
            let list = try await episodes
            let stateList = try await states
            var map: [Int: BangumiEpisodeCollectionType] = [:]
            for entry in stateList {
                map[entry.episode.id] = entry.type
            }
            episodeLists[subjectID] = list
            episodeStates[subjectID] = map
        } catch {
            handle(error)
        }
    }

    /// 改单集状态。
    ///
    /// 走批量接口（只传一个 id）：bgm 会在这条接口上顺带重算收藏的 `ep_status`，
    /// 单集 PUT 不会。条目没收藏过时 bgm 直接 400，所以先补一条「在看」；
    /// 看过一集后「想看」也升成「在看」。
    public func setEpisodeState(
        _ type: BangumiEpisodeCollectionType,
        subjectID: Int,
        episode: BangumiEpisode,
        item: BangumiItem? = nil
    ) async {
        guard subjectID > 0, auth.isLoggedIn else { return }
        var map = episodeStates[subjectID] ?? [:]
        let previous = map[episode.id] ?? .none
        guard previous != type else { return }

        // 先保证条目在收藏里，否则下面的 PATCH 会被 400 打回。
        if collections[subjectID] == nil {
            guard let item else { return }
            await setCollection(.doing, for: item)
            guard collections[subjectID] != nil else { return }
        }

        map[episode.id] = type
        episodeStates[subjectID] = map

        do {
            let token = try await auth.validAccessToken()
            try await api.updateEpisodeCollections(
                subjectID: subjectID,
                episodeIDs: [episode.id],
                type: type,
                token: token
            )
            lastError = nil
            reflectProgressLocally(subjectID: subjectID)
            if type.isWatched {
                await promoteToDoingIfNeeded(subjectID: subjectID, item: item, token: token)
            }
        } catch {
            var rollback = episodeStates[subjectID] ?? [:]
            rollback[episode.id] = previous
            episodeStates[subjectID] = rollback
            handle(error)
        }
    }

    /// bgm 在批量接口上重算了 `ep_status`，接口没有返回体，这里按本地已看数估一份，
    /// 让详情页「已看 N 集」立即对上；下次 `syncAll` 会被服务端的值覆盖。
    private func reflectProgressLocally(subjectID: Int) {
        guard let current = collections[subjectID] else { return }
        let watched = watchedCount(subjectID: subjectID)
        guard watched != current.epStatus else { return }
        collections[subjectID] = current.withEpStatus(watched)
        persistCache()
    }

    /// 看了一集的「想看」升成「在看」。只改 type，`ep_status` 交给服务端。
    private func promoteToDoingIfNeeded(subjectID: Int, item: BangumiItem?, token: String) async {
        guard let current = collections[subjectID], current.type == .wish else { return }
        let optimistic = current.withType(.doing)
        collections[subjectID] = optimistic
        do {
            try await api.updateSubjectCollection(
                subjectID: subjectID,
                update: BangumiCollectionUpdate(type: .doing),
                token: token
            )
            persistCache()
        } catch {
            collections[subjectID] = current
            handle(error)
        }
    }

    // MARK: - PlaybackProgressTracking

    public func playbackStarted(_ request: PlaybackRequest) {
        guard autoTrackPlayback, auth.isLoggedIn, let subjectID = Self.subjectID(for: request) else { return }
        let item = request.item
        Task { [weak self] in
            guard let self else { return }
            await self.loadEpisodeStates(subjectID: subjectID)
            // 开播即「在看」：没收藏或还在「想看」的升成在看，其它状态不动。
            let currentType = self.collections[subjectID]?.type
            if currentType == nil || currentType == .wish, let item {
                await self.setCollection(.doing, for: item)
            }
        }
    }

    public func playbackProgressed(_ request: PlaybackRequest, positionMs: Int, durationMs: Int) {
        guard autoTrackPlayback, auth.isLoggedIn, let subjectID = Self.subjectID(for: request) else { return }
        guard BangumiWatchedPolicy.isWatched(positionMs: positionMs, durationMs: durationMs) else { return }
        let key = "\(subjectID):\(request.episodeIndex)"
        guard !markedWatched.contains(key) else { return }
        markedWatched.insert(key)
        let episodeIndex = request.episodeIndex
        let item = request.item
        Task { [weak self] in
            guard let self else { return }
            await self.loadEpisodeStates(subjectID: subjectID)
            guard
                let list = self.episodeLists[subjectID],
                let episode = BangumiEpisode.match(episodeIndex: episodeIndex, in: list)
            else {
                self.markedWatched.remove(key)
                return
            }
            guard self.episodeState(subjectID: subjectID, episodeID: episode.id) != .done else { return }
            await self.setEpisodeState(.done, subjectID: subjectID, episode: episode, item: item)
            // 推送失败（已回滚）就放开去重，下一次暂停 / 关闭还有机会补上。
            if !self.episodeState(subjectID: subjectID, episodeID: episode.id).isWatched {
                self.markedWatched.remove(key)
            }
        }
    }

    /// 播放请求携带的条目号。从「继续观看」进来的是合成条目（id 0），拿不到就不追踪。
    nonisolated static func subjectID(for request: PlaybackRequest) -> Int? {
        guard let id = request.item?.id, id > 0 else { return nil }
        return id
    }

    // MARK: - Errors

    private func handle(_ error: any Error) {
        if case BangumiAPIError.http(let status) = error, status == 401 {
            auth.handleUnauthorized()
            clear()
            return
        }
        if case BangumiAPIError.cancelled = error { return }
        lastError = BangumiAuthStore.describe(error)
    }

    // MARK: - Cache

    public static func defaultCacheFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Tube", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bangumi-collections.json", isDirectory: false)
    }

    private struct CacheEnvelope: Codable {
        var userID: Int
        var syncedAt: Date
        var collections: [BangumiUserCollection]
    }

    private func restoreCache() {
        guard
            auth.isLoggedIn,
            let data = try? Data(contentsOf: cacheFileURL),
            let envelope = try? JSONDecoder().decode(CacheEnvelope.self, from: data)
        else { return }
        // 换了账号就不用上一个人的缓存。
        if let userID = auth.user?.id, userID != envelope.userID { return }
        var map: [Int: BangumiUserCollection] = [:]
        for collection in envelope.collections where collection.subjectID > 0 {
            map[collection.subjectID] = collection
        }
        collections = map
        lastSyncedAt = envelope.syncedAt
        lastSyncedUserID = envelope.userID
    }

    private func persistCache() {
        let envelope = CacheEnvelope(
            userID: auth.user?.id ?? lastSyncedUserID ?? 0,
            syncedAt: lastSyncedAt ?? .now,
            collections: Array(collections.values)
        )
        let url = cacheFileURL
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
