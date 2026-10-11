import Foundation
import Testing
@testable import TubeKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 登录态接口的请求形态：路径、方法、Authorization 头、请求体字段。
///
/// 自己一套 URLProtocol 桩，不和 `BangumiAPIClientTests` 抢同一个静态 handler；
/// 但 suite 内部仍要串行 —— handler 是静态的。
@Suite("BangumiAccountAPI", .serialized)
struct BangumiAccountAPITests {

    private func makeClient(_ handler: @escaping @Sendable (AccountStubURLProtocol.Captured) -> (Int, Data)) -> BangumiAPIClient {
        BangumiAPIClient(session: .accountStub(handler: handler))
    }

    @Test("me hits /v0/me with a bearer token")
    func me() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/me")
            #expect(req.method == "GET")
            #expect(req.headers["Authorization"] == "Bearer tok")
            return (200, Data(#"{"id": 1, "username": "u", "nickname": "n"}"#.utf8))
        }
        let user = try await client.me(token: "tok")
        #expect(user.id == 1)
        #expect(user.nickname == "n")
    }

    @Test("collections lists anime only with paging query")
    func collections() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/users/sai/collections")
            let q = req.query
            #expect(q["subject_type"] == "2")
            #expect(q["type"] == "3")
            #expect(q["limit"] == "2")
            #expect(q["offset"] == "4")
            #expect(req.headers["Authorization"] == "Bearer tok")
            return (200, Data(#"{"data": [{"subject_id": 10, "type": 3}, {"subject_id": 11, "type": 3}], "total": 7, "limit": 2, "offset": 4}"#.utf8))
        }
        let page = try await client.collections(username: "sai", type: .doing, limit: 2, offset: 4, token: "tok")
        #expect(page.items.map(\.subjectID) == [10, 11])
        #expect(page.total == 7)
        #expect(page.nextOffset == 6)
        #expect(page.hasMore)
    }

    @Test("subjectCollection maps 404 to nil")
    func subjectCollectionNotFound() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/users/-/collections/8")
            return (404, Data(#"{"title":"Not Found"}"#.utf8))
        }
        let c = try await client.subjectCollection(subjectID: 8, token: "tok")
        #expect(c == nil)
    }

    @Test("updateSubjectCollection POSTs JSON with type and ep_status")
    func updateSubjectCollection() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/users/-/collections/8")
            #expect(req.method == "POST")
            #expect(req.headers["Content-Type"] == "application/json")
            #expect(req.headers["Authorization"] == "Bearer tok")
            let body = req.jsonBody
            #expect(body["type"] as? Int == 3)
            #expect(body["ep_status"] as? Int == 4)
            return (202, Data())
        }
        try await client.updateSubjectCollection(
            subjectID: 8,
            update: BangumiCollectionUpdate(type: .doing, epStatus: 4),
            token: "tok"
        )
    }

    @Test("episodeCollections requests main episodes and maps 404 to empty")
    func episodeCollections() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/users/-/collections/8/episodes")
            #expect(req.query["episode_type"] == "0")
            return (200, Data(#"{"data": [{"episode": {"id": 100, "ep": 1, "sort": 1}, "type": 2}, {"episode": {"id": 101, "ep": 2, "sort": 2}, "type": 0}]}"#.utf8))
        }
        let states = try await client.episodeCollections(subjectID: 8, token: "tok")
        #expect(states.map(\.episode.id) == [100, 101])
        #expect(states[0].type == .done)
        #expect(states[1].type == .none)

        let missing = makeClient { _ in (404, Data()) }
        let empty = try await missing.episodeCollections(subjectID: 8, token: "tok")
        #expect(empty.isEmpty)
    }

    @Test("updateEpisodeCollection PUTs the single-episode endpoint")
    func updateEpisode() async throws {
        let client = makeClient { req in
            #expect(req.url.path == "/v0/users/-/collections/-/episodes/100")
            #expect(req.method == "PUT")
            #expect(req.jsonBody["type"] as? Int == 2)
            return (204, Data())
        }
        try await client.updateEpisodeCollection(episodeID: 100, type: .done, token: "tok")
    }

    @Test("updateEpisodeCollections PATCHes a batch and skips empty input")
    func updateEpisodesBatch() async throws {
        let hit = Locked(0)
        let client = makeClient { req in
            hit.value += 1
            #expect(req.url.path == "/v0/users/-/collections/8/episodes")
            #expect(req.method == "PATCH")
            #expect(req.jsonBody["episode_id"] as? [Int] == [1, 2])
            #expect(req.jsonBody["type"] as? Int == 2)
            return (204, Data())
        }
        try await client.updateEpisodeCollections(subjectID: 8, episodeIDs: [], type: .done, token: "tok")
        #expect(hit.value == 0)
        try await client.updateEpisodeCollections(subjectID: 8, episodeIDs: [1, 2], type: .done, token: "tok")
        #expect(hit.value == 1)
    }

    @Test("401 surfaces as http error so the auth store can log out")
    func unauthorized() async {
        let client = makeClient { _ in (401, Data()) }
        await #expect(throws: BangumiAPIError.http(status: 401)) {
            _ = try await client.me(token: "bad")
        }
    }

    @Test("token exchange posts grant fields and maps expires_in to an absolute date")
    func tokenExchange() async throws {
        let session = URLSession.accountStub { req in
            #expect(req.url.absoluteString == "https://bgm.tv/oauth/access_token")
            #expect(req.method == "POST")
            let body = req.jsonBody
            #expect(body["grant_type"] as? String == "authorization_code")
            #expect(body["code"] as? String == "c0de")
            #expect(body["client_id"] as? String == "cid")
            #expect(body["redirect_uri"] as? String == "nembx-tube://bangumi-auth")
            return (200, Data(#"{"access_token": "at", "expires_in": 3600, "token_type": "Bearer", "refresh_token": "rt", "user_id": 9}"#.utf8))
        }
        let client = BangumiOAuthClient(
            config: BangumiOAuthConfig(clientID: "cid", clientSecret: "sec", redirectURI: "nembx-tube://bangumi-auth"),
            session: session
        )
        let before = Date()
        let token = try await client.exchange(code: "c0de")
        #expect(token.accessToken == "at")
        #expect(token.refreshToken == "rt")
        #expect(token.userID == 9)
        #expect(token.expiresAt.timeIntervalSince(before) > 3500)
    }

    @Test("refresh keeps the previous user id when the response omits it")
    func tokenRefreshKeepsUserID() async throws {
        let session = URLSession.accountStub { req in
            #expect(req.jsonBody["grant_type"] as? String == "refresh_token")
            #expect(req.jsonBody["refresh_token"] as? String == "old")
            return (200, Data(#"{"access_token": "new", "expires_in": 10, "refresh_token": "rt2"}"#.utf8))
        }
        let client = BangumiOAuthClient(
            config: BangumiOAuthConfig(clientID: "cid", clientSecret: "sec", redirectURI: "x://y"),
            session: session
        )
        let old = BangumiToken(accessToken: "a", refreshToken: "old", expiresAt: .now, userID: 5)
        let refreshed = try await client.refresh(old)
        #expect(refreshed.accessToken == "new")
        #expect(refreshed.refreshToken == "rt2")
        #expect(refreshed.userID == 5)
    }
}

// MARK: - Stub

extension URLSession {
    static func accountStub(
        handler: @escaping @Sendable (AccountStubURLProtocol.Captured) -> (Int, Data)
    ) -> URLSession {
        AccountStubURLProtocol.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [AccountStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

/// 可被子类覆盖 handler 存储的桩：每个 suite 用自己的子类，静态 handler 才不会跨 suite 互相覆盖
/// （Swift Testing 的 suite 之间是并行跑的）。
class AccountStubURLProtocol: URLProtocol, @unchecked Sendable {
    /// 请求的快照。URLProtocol 看到的 body 在 `httpBodyStream` 里，这里先读出来。
    struct Captured: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data

        var query: [String: String] {
            var map: [String: String] = [:]
            for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                map[item.name] = item.value
            }
            return map
        }

        var jsonBody: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }
    }

    nonisolated(unsafe) private static var storage: (@Sendable (Captured) -> (Int, Data))?
    class var handler: (@Sendable (Captured) -> (Int, Data))? {
        get { storage }
        set { storage = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = type(of: self).handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let captured = Captured(
            url: request.url ?? URL(string: "http://stub")!,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.readBody(of: request)
        )
        let (status, body) = handler(captured)
        let response = HTTPURLResponse(
            url: captured.url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
