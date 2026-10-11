import Foundation
import Testing
@testable import TubeKit

/// 账户 / 收藏相关纯模型的解码与策略。不碰网络。
@Suite("BangumiAccountModels")
struct BangumiAccountModelsTests {

    // MARK: - /v0/me

    @Test("decodes /v0/me with nested avatar and falls back nickname to username")
    func decodesMe() throws {
        let json = """
            {"id": 42, "username": "sai", "nickname": "",
             "avatar": {"large": "//lain.bgm.tv/pic/user/l/1.jpg", "medium": "//lain.bgm.tv/pic/user/m/1.jpg", "small": ""},
             "sign": "hi", "user_group": 10}
            """
        let user = try JSONDecoder().decode(BangumiUser.self, from: Data(json.utf8))
        #expect(user.id == 42)
        #expect(user.username == "sai")
        #expect(user.nickname == "sai")
        #expect(user.displayName == "sai")
        #expect(user.avatarURL?.absoluteString == "https://lain.bgm.tv/pic/user/m/1.jpg")

        // 往返编码保留头像
        let data = try JSONEncoder().encode(user)
        let back = try JSONDecoder().decode(BangumiUser.self, from: data)
        #expect(back == user)
    }

    // MARK: - Collections

    @Test("decodes a user collection with subject and tolerates unknown type")
    func decodesCollection() throws {
        let json = """
            {"subject_id": 8, "subject_type": 2, "type": 3, "rate": 8, "ep_status": 5, "vol_status": 0,
             "updated_at": "2024-04-09T22:20:00+08:00", "private": false, "comment": "nice", "tags": ["a","b"],
             "subject": {"id": 8, "name": "Name", "name_cn": "中文", "date": "2024-04-01",
                         "images": {"large": "l", "common": "c", "medium": "m", "small": "s", "grid": "g"},
                         "rating": {"rank": 10, "score": 8.1, "total": 100}, "eps": 12}}
            """
        let c = try JSONDecoder().decode(BangumiUserCollection.self, from: Data(json.utf8))
        #expect(c.subjectID == 8)
        #expect(c.type == .doing)
        #expect(c.epStatus == 5)
        #expect(c.rate == 8)
        #expect(c.tags == ["a", "b"])
        #expect(c.subject?.nameCn == "中文")

        let weird = try JSONDecoder().decode(
            BangumiUserCollection.self,
            from: Data(#"{"subject_id": 1, "type": 99}"#.utf8)
        )
        #expect(weird.type == .wish)
        #expect(weird.subject == nil)
    }

    @Test("collection round-trips through the on-disk cache encoding")
    func collectionRoundTrip() throws {
        let original = BangumiUserCollection(
            subjectID: 7, type: .collect, epStatus: 12, rate: 9, comment: "x", isPrivate: true,
            tags: ["t"], updatedAt: "2024-01-01T00:00:00Z",
            subject: BangumiItem(id: 7, name: "n", nameCn: "c", summary: "", airDate: "", rank: 0, ratingScore: 0, images: .empty, tags: [])
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(BangumiUserCollection.self, from: data)
        #expect(back.subjectID == 7)
        #expect(back.type == .collect)
        #expect(back.epStatus == 12)
        #expect(back.isPrivate == true)
        #expect(back.subject?.id == 7)
    }

    @Test("decodes episode collection entries")
    func decodesEpisodeCollection() throws {
        let json = """
            {"episode": {"id": 1001, "ep": 1, "sort": 1, "name": "ep1", "name_cn": "第一集", "airdate": "2024-01-01", "comment": 3},
             "type": 2}
            """
        let e = try JSONDecoder().decode(BangumiUserEpisodeCollection.self, from: Data(json.utf8))
        #expect(e.episode.id == 1001)
        #expect(e.type == .done)
        #expect(e.type.isWatched)
    }

    @Test("collection update body only carries the fields that were set")
    func updateBodyEncoding() throws {
        let data = try JSONEncoder().encode(BangumiCollectionUpdate(type: .doing, epStatus: 3))
        let dict = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(dict["type"] as? Int == 3)
        #expect(dict["ep_status"] as? Int == 3)
        #expect(dict["comment"] == nil)
        #expect(dict["private"] == nil)
    }

    // MARK: - Token

    @Test("token expiry respects leeway and distantFuture never expires")
    func tokenExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let soon = BangumiToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(100))
        #expect(soon.isExpired(now: now))
        #expect(!soon.isExpired(now: now, leeway: 0))
        let manual = BangumiToken(accessToken: "a", refreshToken: "", expiresAt: .distantFuture)
        #expect(!manual.isExpired(now: now))
        #expect(!manual.canRefresh)
        #expect(soon.canRefresh)
    }

    @Test("oauth config reports configured only when both id and secret are present")
    func oauthConfig() {
        let empty = BangumiOAuthConfig(clientID: "", clientSecret: "", redirectURI: "nembx-tube://bangumi-auth")
        #expect(!empty.isConfigured)
        #expect(empty.callbackScheme == "nembx-tube")
        let full = BangumiOAuthConfig(clientID: "id", clientSecret: "s", redirectURI: "nembx-tube://bangumi-auth")
        #expect(full.isConfigured)
    }

    @Test("bundle config falls back to the default redirect when xcconfig truncated it")
    func bundleRedirectFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bgm-cfg-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "BangumiClientID": "cid", "BangumiClientSecret": "sec",
            "BangumiRedirectURI": "nembx-tube:",  // xcconfig 把 `//bangumi-auth` 当注释吃掉后的残值
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: dir.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: dir))
        let config = BangumiOAuthConfig.fromBundle(bundle)
        #expect(config.isConfigured)
        #expect(config.redirectURI == BangumiOAuthConfig.defaultRedirectURI)
        #expect(config.callbackScheme == "nembx-tube")
    }

    @Test("authorize URL carries client_id, response_type, redirect_uri and state")
    func authorizeURL() async throws {
        let client = BangumiOAuthClient(
            config: BangumiOAuthConfig(clientID: "cid", clientSecret: "sec", redirectURI: "nembx-tube://bangumi-auth")
        )
        let url = try #require(await client.makeAuthorizeURL(state: "s1"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.host == "bgm.tv")
        #expect(url.path == "/oauth/authorize")
        #expect(value("client_id") == "cid")
        #expect(value("response_type") == "code")
        #expect(value("redirect_uri") == "nembx-tube://bangumi-auth")
        #expect(value("state") == "s1")
    }

    @Test("callback code extraction: state checked only when echoed back")
    func callbackExtraction() throws {
        let withState = URL(string: "nembx-tube://bangumi-auth?code=abc&state=xyz")!
        #expect(try BangumiAuthStore.extractCode(from: withState, expectedState: "xyz") == "abc")

        // bgm 文档没承诺回传 state —— 不带也要放行
        let noState = URL(string: "nembx-tube://bangumi-auth?code=abc")!
        #expect(try BangumiAuthStore.extractCode(from: noState, expectedState: "xyz") == "abc")
        #expect(try BangumiAuthStore.extractCode(from: noState, expectedState: nil) == "abc")

        let bad = URL(string: "nembx-tube://bangumi-auth?code=abc&state=other")!
        #expect(throws: BangumiAuthError.stateMismatch) {
            try BangumiAuthStore.extractCode(from: bad, expectedState: "xyz")
        }

        let noCode = URL(string: "nembx-tube://bangumi-auth?state=xyz")!
        #expect(throws: BangumiAuthError.callbackMissingCode) {
            try BangumiAuthStore.extractCode(from: noCode, expectedState: "xyz")
        }
    }

    // MARK: - Watched policy

    @Test("watched policy: min(90%, duration - 100s), ignoring clips under 10s")
    func watchedPolicy() {
        let duration = 24 * 60 * 1000  // 1_440_000
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: 0, durationMs: duration))
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: duration / 2, durationMs: duration))
        // 90% = 1_296_000，比「剩 100 秒」(1_340_000) 更早，取较早者
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: 1_290_000, durationMs: duration))
        #expect(BangumiWatchedPolicy.isWatched(positionMs: 1_296_000, durationMs: duration))
        #expect(BangumiWatchedPolicy.isWatched(positionMs: duration - 60_000, durationMs: duration))
        // 没拿到时长 / 太短时不能误判
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: 10_000, durationMs: 0))
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: 9_000, durationMs: 9_500))
        // 短片：3 分钟的片，「剩 100 秒」(80s) 比 90% (162s) 更早
        #expect(!BangumiWatchedPolicy.isWatched(positionMs: 70_000, durationMs: 180_000))
        #expect(BangumiWatchedPolicy.isWatched(positionMs: 85_000, durationMs: 180_000))
    }

    @Test("progress label wording")
    func progressLabel() {
        #expect(BangumiProgressLabel.text(watched: 0, total: 0) == nil)
        #expect(BangumiProgressLabel.text(watched: 3, total: 12) == "已看 3 / 12 集")
        #expect(BangumiProgressLabel.text(watched: 15, total: 12) == "已看 12 / 12 集")
        #expect(BangumiProgressLabel.text(watched: 2, total: 0) == "已看 2 集")
    }

    @Test("collection type labels match bgm wording")
    func typeLabels() {
        #expect(BangumiCollectionType.wish.label == "想看")
        #expect(BangumiCollectionType.collect.label == "看过")
        #expect(BangumiCollectionType.doing.label == "在看")
        #expect(BangumiCollectionType.onHold.label == "搁置")
        #expect(BangumiCollectionType.dropped.label == "抛弃")
        #expect(BangumiCollectionType.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(BangumiCollectionFilterBar.order[0] == nil)
        #expect(BangumiCollectionFilterBar.order.count == BangumiCollectionType.allCases.count + 1)
    }
}
