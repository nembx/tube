import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 需要登录态的 Bangumi 接口。全部走 `api.bgm.tv/v0`，带 `Authorization: Bearer`。
///
/// token 由调用方（`BangumiAuthStore`）负责续期后再传进来，client 不持有登录状态 ——
/// 这样 `BangumiAPIClient.shared` 仍然是无状态的，单测也不用先登录。
public protocol BangumiAccountAPIProtocol: Sendable {
    /// `GET /v0/me`
    func me(token: String) async throws -> BangumiUser
    /// `GET /v0/users/{username}/collections`，只拿动画（subject_type=2）。
    func collections(
        username: String,
        type: BangumiCollectionType?,
        limit: Int,
        offset: Int,
        token: String
    ) async throws -> BangumiUserCollectionPage
    /// `GET /v0/users/-/collections/{subject_id}`。没收藏过返回 nil。
    func subjectCollection(subjectID: Int, token: String) async throws -> BangumiUserCollection?
    /// `POST /v0/users/-/collections/{subject_id}`，新增或修改。
    func updateSubjectCollection(
        subjectID: Int,
        update: BangumiCollectionUpdate,
        token: String
    ) async throws
    /// `GET /v0/users/-/collections/{subject_id}/episodes`，只拿正片。
    func episodeCollections(subjectID: Int, token: String) async throws -> [BangumiUserEpisodeCollection]
    /// `PATCH /v0/users/-/collections/{subject_id}/episodes`，批量改单集状态。
    /// 服务端会顺带重算收藏的 `ep_status`；条目没收藏过会 400。
    func updateEpisodeCollections(
        subjectID: Int,
        episodeIDs: [Int],
        type: BangumiEpisodeCollectionType,
        token: String
    ) async throws
    /// `PUT /v0/users/-/collections/-/episodes/{episode_id}`，改单集状态。
    func updateEpisodeCollection(
        episodeID: Int,
        type: BangumiEpisodeCollectionType,
        token: String
    ) async throws
}

/// 收藏列表的一页。
public struct BangumiUserCollectionPage: Hashable, Sendable {
    public let items: [BangumiUserCollection]
    public let total: Int
    public let nextOffset: Int

    public init(items: [BangumiUserCollection], total: Int, nextOffset: Int) {
        self.items = items
        self.total = total
        self.nextOffset = nextOffset
    }

    public var hasMore: Bool { nextOffset < total }
}

extension BangumiAPIClient: BangumiAccountAPIProtocol {
    public func me(token: String) async throws -> BangumiUser {
        let req = try makeAuthorizedRequest(path: "/v0/me", token: token)
        let data = try await perform(req)
        return try decode(BangumiUser.self, from: data)
    }

    public func collections(
        username: String,
        type: BangumiCollectionType?,
        limit: Int = 50,
        offset: Int = 0,
        token: String
    ) async throws -> BangumiUserCollectionPage {
        guard
            let escaped = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            var components = URLComponents(
                url: apiDomain.appendingPathComponent("/v0/users/\(escaped)/collections"),
                resolvingAgainstBaseURL: false
            )
        else {
            throw BangumiAPIError.invalidURL
        }
        var query = [
            URLQueryItem(name: "subject_type", value: "2"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let type {
            query.append(URLQueryItem(name: "type", value: String(type.rawValue)))
        }
        components.queryItems = query
        guard let url = components.url else { throw BangumiAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        applyAuthorization(token, to: &req)
        let data = try await perform(req)
        let envelope = try decode(CollectionsEnvelope.self, from: data)
        return BangumiUserCollectionPage(
            items: envelope.data,
            total: envelope.total ?? envelope.data.count,
            nextOffset: offset + envelope.data.count
        )
    }

    public func subjectCollection(subjectID: Int, token: String) async throws -> BangumiUserCollection? {
        let req = try makeAuthorizedRequest(
            path: "/v0/users/-/collections/\(subjectID)",
            token: token
        )
        do {
            let data = try await perform(req)
            return try decode(BangumiUserCollection.self, from: data)
        } catch BangumiAPIError.http(let status) where status == 404 {
            return nil
        }
    }

    public func updateSubjectCollection(
        subjectID: Int,
        update: BangumiCollectionUpdate,
        token: String
    ) async throws {
        var req = try makeAuthorizedRequest(
            path: "/v0/users/-/collections/\(subjectID)",
            token: token
        )
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(update)
        _ = try await perform(req)
    }

    public func episodeCollections(subjectID: Int, token: String) async throws -> [BangumiUserEpisodeCollection] {
        var components = URLComponents(
            url: apiDomain.appendingPathComponent("/v0/users/-/collections/\(subjectID)/episodes"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "episode_type", value: "0"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let url = components?.url else { throw BangumiAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        applyAuthorization(token, to: &req)
        do {
            let data = try await perform(req)
            return try decode(EpisodeCollectionsEnvelope.self, from: data).data
        } catch BangumiAPIError.http(let status) where status == 404 {
            // 没收藏过这个条目时 bgm 直接 404，对调用方来说就是「一集都没看」。
            return []
        }
    }

    public func updateEpisodeCollections(
        subjectID: Int,
        episodeIDs: [Int],
        type: BangumiEpisodeCollectionType,
        token: String
    ) async throws {
        guard !episodeIDs.isEmpty else { return }
        var req = try makeAuthorizedRequest(
            path: "/v0/users/-/collections/\(subjectID)/episodes",
            token: token
        )
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            EpisodeBatchBody(episodeID: episodeIDs, type: type.rawValue)
        )
        _ = try await perform(req)
    }

    public func updateEpisodeCollection(
        episodeID: Int,
        type: BangumiEpisodeCollectionType,
        token: String
    ) async throws {
        var req = try makeAuthorizedRequest(
            path: "/v0/users/-/collections/-/episodes/\(episodeID)",
            token: token
        )
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["type": type.rawValue])
        _ = try await perform(req)
    }

    // MARK: - internals

    private func makeAuthorizedRequest(path: String, token: String) throws -> URLRequest {
        var req = URLRequest(url: apiDomain.appendingPathComponent(path))
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        applyAuthorization(token, to: &req)
        return req
    }

    private func applyAuthorization(_ token: String, to req: inout URLRequest) {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }
}

// MARK: - Envelopes

private struct CollectionsEnvelope: Decodable {
    let data: [BangumiUserCollection]
    let total: Int?
}

private struct EpisodeCollectionsEnvelope: Decodable {
    let data: [BangumiUserEpisodeCollection]
}

private struct EpisodeBatchBody: Encodable {
    let episodeID: [Int]
    let type: Int

    private enum CodingKeys: String, CodingKey {
        case episodeID = "episode_id"
        case type
    }
}
