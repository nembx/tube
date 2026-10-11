import Foundation
import Testing
@testable import TubeKit

/// `BangumiAuthStore` + `BangumiCollectionStore` 的行为：登录态、同步合并、
/// 乐观更新与回滚、播放进度驱动的「看过」。全部用假 API，不碰网络与 Keychain。
@Suite("BangumiCollectionStore")
@MainActor
struct BangumiCollectionStoreTests {

    // MARK: - Fakes

    final class FakeAccountAPI: BangumiAccountAPIProtocol, @unchecked Sendable {
        var user = BangumiUser(id: 7, username: "sai", nickname: "Sai")
        /// 远端全量收藏；按 `serverPageSize` 切页，和客户端传的 limit 无关 ——
        /// bgm 真实行为也是服务端说了算，客户端拿 `nextOffset` 继续翻。
        var remote: [BangumiUserCollection] = []
        var serverPageSize = 1
        var episodeStates: [Int: [BangumiUserEpisodeCollection]] = [:]
        var failNextSubjectUpdate: (any Error)?
        var failNextEpisodeUpdate: (any Error)?
        var meError: (any Error)?

        private(set) var subjectUpdates: [(Int, BangumiCollectionUpdate)] = []
        private(set) var episodeUpdates: [(Int, BangumiEpisodeCollectionType)] = []
        private(set) var collectionsCalls = 0

        func me(token: String) async throws -> BangumiUser {
            if let meError { throw meError }
            return user
        }

        func collections(
            username: String, type: BangumiCollectionType?, limit: Int, offset: Int, token: String
        ) async throws -> BangumiUserCollectionPage {
            collectionsCalls += 1
            let start = min(offset, remote.count)
            let end = min(start + serverPageSize, remote.count)
            let items = Array(remote[start..<end])
            return BangumiUserCollectionPage(items: items, total: remote.count, nextOffset: offset + items.count)
        }

        func subjectCollection(subjectID: Int, token: String) async throws -> BangumiUserCollection? { nil }

        func updateSubjectCollection(subjectID: Int, update: BangumiCollectionUpdate, token: String) async throws {
            if let failNextSubjectUpdate {
                self.failNextSubjectUpdate = nil
                throw failNextSubjectUpdate
            }
            subjectUpdates.append((subjectID, update))
        }

        func episodeCollections(subjectID: Int, token: String) async throws -> [BangumiUserEpisodeCollection] {
            episodeStates[subjectID] ?? []
        }

        /// store 走批量接口（一次一个 id），这里把每个 id 拆开记录。
        func updateEpisodeCollections(
            subjectID: Int, episodeIDs: [Int], type: BangumiEpisodeCollectionType, token: String
        ) async throws {
            if let failNextEpisodeUpdate {
                self.failNextEpisodeUpdate = nil
                throw failNextEpisodeUpdate
            }
            for id in episodeIDs { episodeUpdates.append((id, type)) }
        }

        func updateEpisodeCollection(episodeID: Int, type: BangumiEpisodeCollectionType, token: String) async throws {
            episodeUpdates.append((episodeID, type))
        }
    }

    final class FakeSubjectAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        var episodes: [Int: [BangumiEpisode]] = [:]

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(keyword: String, sort: BangumiSearchSort, filter: BangumiSearchFilter, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            BangumiItem(id: subjectID, name: "", nameCn: "", summary: "", airDate: "", rank: 0, ratingScore: 0, images: .empty, tags: [])
        }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { episodes[subjectID] ?? [] }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { [] }
    }

    final class FakeFollowMirror: FollowMirroring {
        private(set) var inserted: [BangumiItem] = []

        func insert(_ item: BangumiItem, updatedAt: Date) throws -> Bool {
            guard !inserted.contains(where: { $0.id == item.id }) else { return false }
            inserted.append(item)
            return true
        }

        func insertMissing(_ items: [BangumiItem]) throws {
            for item in items { _ = try insert(item, updatedAt: .now) }
        }
    }

    struct Harness {
        let api: FakeAccountAPI
        let subjectAPI: FakeSubjectAPI
        let follow: FakeFollowMirror
        let auth: BangumiAuthStore
        let store: BangumiCollectionStore
        let defaults: UserDefaults
    }

    private func makeHarness(loggedIn: Bool = true) async -> Harness {
        let api = FakeAccountAPI()
        let subjectAPI = FakeSubjectAPI()
        let follow = FakeFollowMirror()
        let suite = "BangumiCollectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let auth = BangumiAuthStore(
            api: api,
            oauthConfig: BangumiOAuthConfig(clientID: "", clientSecret: "", redirectURI: "x://y"),
            defaults: defaults,
            storage: InMemoryTokenStorage()
        )
        if loggedIn {
            let ok = await auth.login(accessToken: "tok")
            #expect(ok)
        }
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgm-store-test-\(UUID().uuidString).json")
        let store = BangumiCollectionStore(
            auth: auth, followStore: follow, api: api, subjectAPI: subjectAPI,
            defaults: defaults, cacheFileURL: cache
        )
        return Harness(api: api, subjectAPI: subjectAPI, follow: follow, auth: auth, store: store, defaults: defaults)
    }

    private func item(_ id: Int, title: String = "番剧") -> BangumiItem {
        BangumiItem(id: id, name: title, nameCn: title, summary: "", airDate: "", rank: 0, ratingScore: 0, images: .empty, tags: [])
    }

    private func episode(_ id: Int, ep: Int) -> BangumiEpisode {
        BangumiEpisode(id: id, ep: Double(ep), sort: Double(ep), name: "ep\(ep)", nameCn: "", airDate: "", commentCount: 0)
    }

    private func request(subject: BangumiItem?, episodeIndex: Int) -> PlaybackRequest {
        let episodes = (0..<3).map { Episode(title: "第\($0 + 1)集", url: URL(string: "https://x/\($0)")!, index: $0) }
        let detail = AnimeDetail(
            title: "番剧",
            detailURL: URL(string: "https://x/detail")!,
            ruleName: "rule",
            roads: [EpisodeRoad(index: 0, label: "线路 1", episodes: episodes)]
        )
        return PlaybackRequest(anime: detail, roadIndex: 0, episodeIndex: episodeIndex, rule: Self.makeRule(), item: subject)
    }

    private static func makeRule() -> TubeRule {
        TubeRule(
            api: "0.1.0", type: "vod", name: "rule", version: "1",
            muliSources: false, useWebview: false, useNativePlayer: false, userAgent: "",
            baseURL: "https://example.com", searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//a", searchName: ".", searchResult: "@href",
            chapterRoads: "//div", chapterResult: "//a",
            usePost: false, useLegacyParser: false, adBlocker: false, referer: "", antiCrawlerConfig: nil
        )
    }

    // MARK: - Auth

    @Test("manual token login validates via /v0/me and persists user")
    func manualLogin() async {
        let h = await makeHarness(loggedIn: false)
        #expect(!h.auth.isLoggedIn)
        let ok = await h.auth.login(accessToken: "  tok  ")
        #expect(ok)
        #expect(h.auth.isLoggedIn)
        #expect(h.auth.user?.username == "sai")
        #expect(h.auth.token?.accessToken == "tok")
        #expect(h.auth.token?.canRefresh == false)
        #expect(h.defaults.data(forKey: BangumiAuthStore.userDefaultsKey) != nil)

        h.auth.logout()
        #expect(!h.auth.isLoggedIn)
        #expect(h.auth.user == nil)
        #expect(h.defaults.data(forKey: BangumiAuthStore.userDefaultsKey) == nil)
    }

    @Test("invalid token is rejected and nothing is persisted")
    func invalidToken() async {
        let h = await makeHarness(loggedIn: false)
        h.api.meError = BangumiAPIError.http(status: 401)
        let ok = await h.auth.login(accessToken: "bad")
        #expect(!ok)
        #expect(!h.auth.isLoggedIn)
        #expect(h.auth.lastError == "令牌无效或已过期")
    }

    @Test("empty token is rejected without a network call")
    func emptyToken() async {
        let h = await makeHarness(loggedIn: false)
        let ok = await h.auth.login(accessToken: "   ")
        #expect(!ok)
        #expect(h.auth.lastError == "令牌不能为空")
    }

    @Test("OAuth callback: beginOAuth arms state, handleCallbackURL exchanges once and ignores strangers")
    func oauthCallback() async throws {
        let api = FakeAccountAPI()
        let suite = "BangumiCollectionStoreTests.oauth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let exchanges = Locked(0)
        let session = URLSession.oauthStub { req in
            exchanges.value += 1
            #expect(req.url.absoluteString == "https://bgm.tv/oauth/access_token")
            #expect(req.jsonBody["code"] as? String == "c0de")
            return (200, Data(#"{"access_token": "at", "expires_in": 604800, "refresh_token": "rt", "user_id": 7}"#.utf8))
        }
        let auth = BangumiAuthStore(
            api: api,
            oauthConfig: BangumiOAuthConfig(clientID: "cid", clientSecret: "sec", redirectURI: "nembx-tube://bangumi-auth"),
            defaults: defaults,
            storage: InMemoryTokenStorage(),
            session: session
        )

        // 没开始授权时，任何回调都不接
        #expect(await auth.handleCallbackURL(URL(string: "nembx-tube://bangumi-auth?code=c0de")!) == false)
        #expect(exchanges.value == 0)

        let url = try #require(await auth.beginOAuth())
        #expect(url.host == "bgm.tv")
        #expect(auth.pendingOAuthState != nil)
        #expect(auth.isOAuthCallback(URL(string: "nembx-tube://bangumi-auth?code=x")!))
        #expect(!auth.isOAuthCallback(URL(string: "https://bgm.tv/oauth?code=x")!))
        #expect(!auth.isOAuthCallback(URL(string: "nembx-tube://other?code=x")!))

        // bgm 不回传 state 也要能登录
        let ok = await auth.handleCallbackURL(URL(string: "nembx-tube://bangumi-auth?code=c0de")!)
        #expect(ok)
        #expect(auth.isLoggedIn)
        #expect(auth.token?.refreshToken == "rt")
        #expect(auth.user?.username == "sai")
        #expect(auth.pendingOAuthState == nil)
        #expect(exchanges.value == 1)

        // 同一回调从第二条路（onOpenURL）再到一次：不重复换码
        #expect(await auth.handleCallbackURL(URL(string: "nembx-tube://bangumi-auth?code=c0de")!) == false)
        #expect(exchanges.value == 1)
    }

    @Test("OAuth callback with a wrong state is rejected and reports an error")
    func oauthStateMismatch() async throws {
        let api = FakeAccountAPI()
        let defaults = UserDefaults(suiteName: "BangumiCollectionStoreTests.oauth2.\(UUID().uuidString)")!
        let auth = BangumiAuthStore(
            api: api,
            oauthConfig: BangumiOAuthConfig(clientID: "cid", clientSecret: "sec", redirectURI: "nembx-tube://bangumi-auth"),
            defaults: defaults,
            storage: InMemoryTokenStorage()
        )
        _ = try #require(await auth.beginOAuth())
        let ok = await auth.handleCallbackURL(URL(string: "nembx-tube://bangumi-auth?code=c0de&state=forged")!)
        #expect(!ok)
        #expect(!auth.isLoggedIn)
        #expect(auth.lastError == BangumiAuthError.stateMismatch.userMessage)
        #expect(auth.pendingOAuthState == nil)
    }

    // MARK: - Sync

    @Test("syncAll pages through collections and mirrors subjects into the follow list")
    func syncAll() async {
        let h = await makeHarness()
        h.api.remote = [
            BangumiUserCollection(subjectID: 1, type: .doing, epStatus: 2, subject: item(1, title: "A")),
            BangumiUserCollection(subjectID: 2, type: .wish, subject: item(2, title: "B")),
        ]
        await h.store.syncAll()
        #expect(h.api.collectionsCalls == 2)
        #expect(h.store.collections.count == 2)
        #expect(h.store.collectionType(for: item(1)) == .doing)
        #expect(h.store.collectionType(for: item(2)) == .wish)
        #expect(h.follow.inserted.map(\.id) == [1, 2])
        #expect(h.store.lastSyncedAt != nil)
        #expect(h.store.count(ofType: .doing) == 1)
        #expect(h.store.filter([item(1), item(2), item(3)], by: .wish).map(\.id) == [2])
        #expect(h.store.filter([item(1), item(2), item(3)], by: nil).count == 3)
    }

    @Test("syncAll is a no-op when logged out")
    func syncLoggedOut() async {
        let h = await makeHarness(loggedIn: false)
        h.api.remote = [BangumiUserCollection(subjectID: 1, type: .doing)]
        await h.store.syncAll()
        #expect(h.api.collectionsCalls == 0)
        #expect(h.store.collections.isEmpty)
    }

    @Test("cache survives a new store instance for the same user")
    func cacheRoundTrip() async throws {
        let h = await makeHarness()
        h.api.remote = [BangumiUserCollection(subjectID: 5, type: .collect, subject: item(5))]
        await h.store.syncAll()
        // 落盘是异步的，等一拍。
        try await Task.sleep(for: .milliseconds(200))

        let cacheURL = try #require(Mirror(reflecting: h.store).descendant("cacheFileURL") as? URL)
        let again = BangumiCollectionStore(
            auth: h.auth, followStore: h.follow, api: h.api, subjectAPI: h.subjectAPI,
            defaults: h.defaults, cacheFileURL: cacheURL
        )
        #expect(again.collectionType(for: item(5)) == .collect)
        #expect(again.lastSyncedAt != nil)
    }

    // MARK: - Subject collection

    @Test("setCollection updates locally first, pushes, and mirrors into follow list")
    func setCollection() async {
        let h = await makeHarness()
        await h.store.setCollection(.wish, for: item(9))
        #expect(h.store.collectionType(for: item(9)) == .wish)
        #expect(h.api.subjectUpdates.count == 1)
        #expect(h.api.subjectUpdates.first?.0 == 9)
        #expect(h.api.subjectUpdates.first?.1.type == .wish)
        #expect(h.follow.inserted.map(\.id) == [9])
        #expect(h.store.lastError == nil)
    }

    @Test("setCollection rolls back when the push fails")
    func setCollectionRollback() async {
        let h = await makeHarness()
        await h.store.setCollection(.doing, for: item(9))
        h.api.failNextSubjectUpdate = BangumiAPIError.http(status: 500)
        await h.store.setCollection(.collect, for: item(9))
        #expect(h.store.collectionType(for: item(9)) == .doing)
        #expect(h.store.lastError == "HTTP 500")
    }

    @Test("setCollection ignores synthetic subjects and logged-out sessions")
    func setCollectionGuards() async {
        let h = await makeHarness()
        await h.store.setCollection(.doing, for: item(0))
        #expect(h.api.subjectUpdates.isEmpty)
        h.auth.logout()
        await h.store.setCollection(.doing, for: item(9))
        #expect(h.api.subjectUpdates.isEmpty)
    }

    @Test("a 401 on push logs the user out and clears remote state")
    func unauthorizedLogsOut() async {
        let h = await makeHarness()
        await h.store.setCollection(.doing, for: item(1))
        h.api.failNextSubjectUpdate = BangumiAPIError.http(status: 401)
        await h.store.setCollection(.collect, for: item(1))
        #expect(!h.auth.isLoggedIn)
        #expect(h.store.collections.isEmpty)
        #expect(h.auth.lastError == "登录已失效，请重新登录")
    }

    // MARK: - Episodes

    @Test("loadEpisodeStates merges the episode list with remote states")
    func loadEpisodeStates() async {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1), episode(101, ep: 2)]
        h.api.episodeStates[3] = [BangumiUserEpisodeCollection(episode: episode(100, ep: 1), type: .done)]
        await h.store.loadEpisodeStates(subjectID: 3)
        #expect(h.store.episodeLists[3]?.count == 2)
        #expect(h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 0))
        #expect(!h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 1))
        #expect(h.store.watchedCount(subjectID: 3) == 1)
    }

    @Test("marking an episode watched promotes wish to doing and reflects progress locally")
    func setEpisodeWatched() async {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1), episode(101, ep: 2)]
        await h.store.setCollection(.wish, for: item(3))
        await h.store.loadEpisodeStates(subjectID: 3)

        await h.store.toggleEpisodeWatched(subjectID: 3, episodeIndex: 1, item: item(3))
        #expect(h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 1))
        #expect(h.api.episodeUpdates.map(\.0) == [101])
        #expect(h.api.episodeUpdates.first?.1 == .done)
        // 想看 → 在看，只改 type；ep_status 由 bgm 在批量接口上重算，不自己推
        let last = h.api.subjectUpdates.last
        #expect(last?.1.type == .doing)
        #expect(last?.1.epStatus == nil)
        #expect(h.store.collectionType(for: item(3)) == .doing)
        // 本地先按已看数估一份，详情页「已看 N 集」立即对上
        #expect(h.store.collection(for: 3)?.epStatus == 1)

        // 再切回未看：只打单集接口，收藏不动
        let updatesBefore = h.api.subjectUpdates.count
        await h.store.toggleEpisodeWatched(subjectID: 3, episodeIndex: 1, item: item(3))
        #expect(!h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 1))
        #expect(h.api.episodeUpdates.last?.1 == BangumiEpisodeCollectionType.none)
        #expect(h.api.subjectUpdates.count == updatesBefore)
        #expect(h.store.collection(for: 3)?.epStatus == 0)
    }

    @Test("marking an episode on an uncollected subject collects it as doing first")
    func setEpisodeAutoCollects() async {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1)]
        await h.store.loadEpisodeStates(subjectID: 3)
        #expect(h.store.collection(for: 3) == nil)

        await h.store.toggleEpisodeWatched(subjectID: 3, episodeIndex: 0, item: item(3))
        // 先 POST 收藏（在看），再 PATCH 单集 —— 否则 bgm 会 400
        #expect(h.api.subjectUpdates.map(\.1.type) == [.doing])
        #expect(h.api.episodeUpdates.map(\.0) == [100])
        #expect(h.store.collectionType(for: item(3)) == .doing)
        #expect(h.follow.inserted.map(\.id) == [3])

        // 没有条目信息就无法补收藏，直接放弃而不是打一个必 400 的请求
        let h2 = await makeHarness()
        h2.subjectAPI.episodes[4] = [episode(200, ep: 1)]
        await h2.store.loadEpisodeStates(subjectID: 4)
        await h2.store.toggleEpisodeWatched(subjectID: 4, episodeIndex: 0, item: nil)
        #expect(h2.api.episodeUpdates.isEmpty)
        #expect(h2.api.subjectUpdates.isEmpty)
    }

    @Test("episode update failure rolls the local state back")
    func setEpisodeRollback() async {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1)]
        await h.store.setCollection(.doing, for: item(3))
        await h.store.loadEpisodeStates(subjectID: 3)
        h.api.failNextEpisodeUpdate = BangumiAPIError.timeout
        await h.store.toggleEpisodeWatched(subjectID: 3, episodeIndex: 0, item: item(3))
        #expect(!h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 0))
        #expect(h.store.lastError == "请求超时")
    }

    // MARK: - Playback tracking

    @Test("playbackStarted marks an uncollected subject as doing")
    func playbackStarted() async throws {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1)]
        h.store.playbackStarted(request(subject: item(3), episodeIndex: 0))
        try await waitUntil { h.store.collectionType(for: item(3)) == .doing }
        #expect(h.api.subjectUpdates.last?.1.type == .doing)
        #expect(h.store.episodeLists[3] != nil)
    }

    @Test("playbackStarted leaves an existing non-wish status alone")
    func playbackStartedKeepsStatus() async throws {
        let h = await makeHarness()
        await h.store.setCollection(.onHold, for: item(3))
        let before = h.api.subjectUpdates.count
        h.store.playbackStarted(request(subject: item(3), episodeIndex: 0))
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.store.collectionType(for: item(3)) == .onHold)
        #expect(h.api.subjectUpdates.count == before)
    }

    @Test("playbackProgressed marks the matching bgm episode watched exactly once")
    func playbackProgressed() async throws {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1), episode(101, ep: 2), episode(102, ep: 3)]
        let req = request(subject: item(3), episodeIndex: 1)

        // 一半：不算看完
        h.store.playbackProgressed(req, positionMs: 600_000, durationMs: 1_200_000)
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.api.episodeUpdates.isEmpty)

        // 过 85%：看完，匹配到 ep 2（id 101）
        h.store.playbackProgressed(req, positionMs: 1_100_000, durationMs: 1_200_000)
        try await waitUntil { h.api.episodeUpdates.count == 1 }
        #expect(h.api.episodeUpdates.first?.0 == 101)
        #expect(h.store.isEpisodeWatched(subjectID: 3, episodeIndex: 1))

        // 同一集再回调（暂停 / 关闭）不重复打接口
        h.store.playbackProgressed(req, positionMs: 1_150_000, durationMs: 1_200_000)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.api.episodeUpdates.count == 1)
    }

    @Test("playback tracking is skipped when auto-track is off or subject is synthetic")
    func playbackTrackingGuards() async throws {
        let h = await makeHarness()
        h.subjectAPI.episodes[3] = [episode(100, ep: 1)]

        h.store.autoTrackPlayback = false
        #expect(h.defaults.bool(forKey: BangumiCollectionStore.autoTrackKey) == false)
        h.store.playbackProgressed(request(subject: item(3), episodeIndex: 0), positionMs: 1_100_000, durationMs: 1_200_000)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.api.episodeUpdates.isEmpty)

        h.store.autoTrackPlayback = true
        h.store.playbackProgressed(request(subject: nil, episodeIndex: 0), positionMs: 1_100_000, durationMs: 1_200_000)
        h.store.playbackProgressed(request(subject: item(0), episodeIndex: 0), positionMs: 1_100_000, durationMs: 1_200_000)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.api.episodeUpdates.isEmpty)
    }

    @Test("clear drops remote state but not the local follow list")
    func clear() async {
        let h = await makeHarness()
        await h.store.setCollection(.doing, for: item(1))
        h.store.clear()
        #expect(h.store.collections.isEmpty)
        #expect(h.store.lastSyncedAt == nil)
        #expect(h.follow.inserted.map(\.id) == [1])
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "timed out waiting for condition")
    }
}

// MARK: - OAuth stub (own handler storage, see AccountStubURLProtocol)

final class OAuthStubURLProtocol: AccountStubURLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var storage: (@Sendable (Captured) -> (Int, Data))?
    override class var handler: (@Sendable (Captured) -> (Int, Data))? {
        get { storage }
        set { storage = newValue }
    }
}

extension URLSession {
    static func oauthStub(
        handler: @escaping @Sendable (AccountStubURLProtocol.Captured) -> (Int, Data)
    ) -> URLSession {
        OAuthStubURLProtocol.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [OAuthStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}
