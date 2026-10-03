import CryptoKit
import Foundation
import SwiftUI

protocol DanmakuProviderProtocol: Sendable {
    func fetchDanmaku(for request: PlaybackRequest) async throws -> [DanmakuComment]
}

enum DanmakuError: LocalizedError, Sendable {
    case missingCredentials
    case unauthorized(statusCode: Int)
    case badResponse(statusCode: Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "缺少DanDanPlay凭证，弹幕暂不可用"
        case .unauthorized(let code):
            return "DanDanPlay 鉴权失败（\(code)），请检查凭证是否正确。"
        case .badResponse(let code):
            return "DanDanPlay 请求失败（HTTP \(code)）。"
        case .invalidPayload:
            return "DanDanPlay 返回的数据无法解析，本集暂无弹幕。"
        }
    }
}

struct DanDanPlayCredentials: Sendable {
    let appID: String
    let appSecret: String

    init?(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        storeSnapshot: DanDanPlayCredentialsStore.Snapshot = DanDanPlayCredentialsStore.snapshot()
    ) {
        // 优先使用用户在设置里填的自定义凭证。
        if let (id, secret) = storeSnapshot.resolvedPair {
            self.appID = id
            self.appSecret = secret
            return
        }

        let infoAppID = (bundle.object(forInfoDictionaryKey: "DanDanPlayAppID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let infoAppSecret = (bundle.object(forInfoDictionaryKey: "DanDanPlayAppSecret") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let envAppID = environment["DANDANPLAY_APP_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let envAppSecret = environment["DANDANPLAY_APP_SECRET"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedAppID = !infoAppID.isEmpty ? infoAppID : envAppID
        let resolvedAppSecret = !infoAppSecret.isEmpty ? infoAppSecret : envAppSecret

        guard !resolvedAppID.isEmpty, !resolvedAppSecret.isEmpty else {
            return nil
        }

        self.appID = resolvedAppID
        self.appSecret = resolvedAppSecret
    }
}

struct DanmakuComment: Hashable, Sendable {
    let text: String
    let time: Double
    let type: Int
    let colorRGB: Int
    let source: String

    var color: Color {
        let red = Double((colorRGB >> 16) & 0xFF) / 255.0
        let green = Double((colorRGB >> 8) & 0xFF) / 255.0
        let blue = Double(colorRGB & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    init(text: String, time: Double, type: Int, colorRGB: Int, source: String) {
        self.text = text
        self.time = time
        self.type = type
        self.colorRGB = colorRGB
        self.source = source
    }

    init?(payload: String, text: String) {
        let parts = payload.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }
        guard
            let time = Double(parts[0]),
            let type = Int(parts[1]),
            let colorRGB = Int(parts[2])
        else {
            return nil
        }

        self.init(
            text: text,
            time: time,
            type: type,
            colorRGB: colorRGB,
            source: String(parts[3])
        )
    }
}

/// DanDanPlay 的响应外层永远是 `{errorCode, success, ...}`，业务字段在失败时会整个缺席
/// （例如 bgm 条目没有对应弹幕库）。所以业务字段一律可选，缺失当作「没有数据」而不是解析失败。
struct DanmakuBangumiInfo: Decodable {
    let bangumi: DanmakuBangumi?
}

struct DanmakuBangumi: Decodable {
    let animeID: Int
    let episodes: [DanmakuBangumiEpisode]

    enum CodingKeys: String, CodingKey {
        case animeID = "animeId"
        case episodes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animeID = try container.decodeIfPresent(Int.self, forKey: .animeID) ?? 0
        episodes = try container.decodeIfPresent([DanmakuBangumiEpisode].self, forKey: .episodes) ?? []
    }
}

struct DanmakuBangumiEpisode: Decodable {
    let episodeID: Int
    let episodeTitle: String

    enum CodingKeys: String, CodingKey {
        case episodeID = "episodeId"
        case episodeTitle
    }
}

struct DanmakuCommentResponse: Decodable {
    let comments: [DanmakuCommentPayload]

    enum CodingKeys: String, CodingKey {
        case comments
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comments = try container.decodeIfPresent([DanmakuCommentPayload].self, forKey: .comments) ?? []
    }
}

struct DanmakuCommentPayload: Decodable {
    let m: String
    let p: String
}

/// 把 DanDanPlay 的响应体解析成领域模型；解析不了时抛出可读的 `invalidPayload`，
/// 而不是让 `DecodingError` 的「未能读取数据，因为数据丢失」直接弹到播放页上。
enum DanmakuResponseParser {
    static func bangumi(from data: Data) throws -> DanmakuBangumi? {
        try decode(DanmakuBangumiInfo.self, from: data).bangumi
    }

    static func comments(from data: Data) throws -> [DanmakuComment] {
        let payload = try decode(DanmakuCommentResponse.self, from: data)
        return payload.comments.compactMap { DanmakuComment(payload: $0.p, text: $0.m) }
            .sorted { $0.time < $1.time }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DanmakuError.invalidPayload
        }
    }
}

actor DanmakuProvider: DanmakuProviderProtocol {
    private let session: URLSession
    private let credentials: DanDanPlayCredentials?
    private let proxyBaseURL: URL?

    init(
        session: URLSession = .shared,
        credentials: DanDanPlayCredentials? = DanDanPlayCredentials(),
        proxySnapshot: DanmakuProxyStore.Snapshot = DanmakuProxyStore.snapshot()
    ) {
        self.session = session
        self.credentials = credentials
        self.proxyBaseURL = proxySnapshot.resolvedBaseURL
    }

    private var apiBaseURL: URL {
        proxyBaseURL ?? URL(string: "https://api.dandanplay.net")!
    }

    private var usesProxy: Bool { proxyBaseURL != nil }

    func fetchDanmaku(for request: PlaybackRequest) async throws -> [DanmakuComment] {
        let requestSummary =
            "anime=\(request.anime.title) episodeTitle=\(request.episode.title) episodeIndex=\(request.episode.index)"
        guard let bangumiID = request.item?.id, bangumiID > 0 else {
            debugLog("skip fetch: missing bangumi item id \(requestSummary)")
            return []
        }
        let episodeNumber = DanmakuEpisodeMatcher.episodeNumber(for: request)
        debugLog("start fetch: bangumiID=\(bangumiID) episodeNumber=\(episodeNumber) \(requestSummary)")
        let danDanBangumiID = try await fetchDanDanBangumiID(bangumiID: bangumiID)
        guard danDanBangumiID > 0 else {
            debugLog("resolved dandan bangumi id is zero: bgm=\(bangumiID)")
            return []
        }
        debugLog("resolved dandan bangumi id: bgm=\(bangumiID) -> dandan=\(danDanBangumiID)")

        let directEpisodeID = syntheticEpisodeID(
            danDanBangumiID: danDanBangumiID,
            episodeNumber: episodeNumber
        )
        debugLog("try direct comment id: \(directEpisodeID)")
        let directComments = try await fetchComments(episodeID: directEpisodeID)
        if !directComments.isEmpty {
            debugLog("direct comment fetch success: episodeID=\(directEpisodeID) count=\(directComments.count)")
            return directComments
        }
        debugLog("direct comment fetch returned empty: episodeID=\(directEpisodeID)")

        let episodeID = try await fetchEpisodeID(bangumiID: bangumiID, episodeNumber: episodeNumber)
        guard let episodeID else {
            debugLog("fallback episode mapping failed: bangumiID=\(bangumiID) episodeNumber=\(episodeNumber)")
            return []
        }
        debugLog("fallback mapped episode id: \(episodeID)")
        let fallbackComments = try await fetchComments(episodeID: episodeID)
        debugLog("fallback comment fetch result: episodeID=\(episodeID) count=\(fallbackComments.count)")
        return fallbackComments
    }

    private func fetchDanDanBangumiID(bangumiID: Int) async throws -> Int {
        guard let url = makeURL(path: "/api/v2/bangumi/bgmtv/\(bangumiID)") else {
            return 0
        }
        debugLog("request bangumi mapping: \(url.absoluteString)")
        let (data, response) = try await perform(url: url)
        try validate(response: response)
        guard let bangumi = try DanmakuResponseParser.bangumi(from: data) else {
            debugLog("bangumi mapping missing in response: bgm=\(bangumiID)")
            return 0
        }
        return bangumi.animeID
    }

    private func fetchEpisodeID(bangumiID: Int, episodeNumber: Int) async throws -> Int? {
        guard let url = makeURL(path: "/api/v2/bangumi/bgmtv/\(bangumiID)") else {
            return nil
        }
        debugLog("request episode mapping: \(url.absoluteString)")
        let (data, response) = try await perform(url: url)
        try validate(response: response)
        guard let bangumi = try DanmakuResponseParser.bangumi(from: data) else {
            debugLog("episode mapping missing in response: bgm=\(bangumiID)")
            return nil
        }
        let episodes = bangumi.episodes
        debugLog("episode mapping candidates: count=\(episodes.count) targetEpisode=\(episodeNumber)")

        if let matched = episodes.first(where: { parsedEpisodeNumber(from: $0.episodeTitle) == episodeNumber }) {
            debugLog("episode mapping matched by title: \(matched.episodeTitle) -> \(matched.episodeID)")
            return matched.episodeID
        }

        let zeroBasedIndex = episodeNumber - 1
        if episodes.indices.contains(zeroBasedIndex) {
            debugLog("episode mapping fallback by index: index=\(zeroBasedIndex) title=\(episodes[zeroBasedIndex].episodeTitle) -> \(episodes[zeroBasedIndex].episodeID)")
            return episodes[zeroBasedIndex].episodeID
        }

        return nil
    }

    private func fetchComments(episodeID: Int) async throws -> [DanmakuComment] {
        guard let url = makeURL(
            path: "/api/v2/comment/\(episodeID)",
            queryItems: [URLQueryItem(name: "withRelated", value: "true")]
        ) else {
            return []
        }
        debugLog("request comments: \(url.absoluteString)")

        let (data, response) = try await perform(url: url)
        try validate(response: response)
        let comments = try DanmakuResponseParser.comments(from: data)
        debugLog("decoded comments: episodeID=\(episodeID) parsed=\(comments.count)")
        return comments
    }

    private func syntheticEpisodeID(danDanBangumiID: Int, episodeNumber: Int) -> Int {
        Int("\(danDanBangumiID)\(String(format: "%04d", episodeNumber))") ?? 0
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            debugLog("bad server response: \(response)")
            throw DanmakuError.badResponse(statusCode: -1)
        }
        if (200..<300).contains(http.statusCode) { return }
        debugLog("bad server response: status=\(http.statusCode)")
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DanmakuError.unauthorized(statusCode: http.statusCode)
        }
        throw DanmakuError.badResponse(statusCode: http.statusCode)
    }

    private func perform(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(RandomUA.next(), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if usesProxy {
            debugLog("proxy request: \(url.absoluteString)")
            return try await session.data(for: request)
        }

        guard let credentials else {
            debugLog("missing credentials: set DanDanPlayAppID / DanDanPlayAppSecret in local config")
            throw DanmakuError.missingCredentials
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        request.setValue("", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Auth")
        request.setValue(credentials.appID, forHTTPHeaderField: "X-AppId")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-Timestamp")
        request.setValue(
            signature(path: url.path, timestamp: timestamp, credentials: credentials),
            forHTTPHeaderField: "X-Signature"
        )
        debugLog(
            "request headers: X-AppId=\(credentials.appID) X-Timestamp=\(timestamp) path=\(url.path)"
        )
        return try await session.data(for: request)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joinedPath = basePath.isEmpty ? path : "/\(basePath)\(path)"
        components.path = joinedPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private func signature(path: String, timestamp: Int, credentials: DanDanPlayCredentials) -> String {
        let raw = credentials.appID + String(timestamp) + path + credentials.appSecret
        let digest = SHA256.hash(data: Data(raw.utf8))
        return Data(digest).base64EncodedString()
    }

    private func debugLog(_ message: String) {
        print("[DanmakuProvider] \(message)")
    }

    private func parsedEpisodeNumber(from title: String) -> Int? {
        let patterns = [
            #"第\s*(\d+)\s*[话話集]"#,
            #"EP?\s*(\d+)"#,
            #"^\s*(\d+)\s*$"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: range),
                    let numberRange = Range(match.range(at: 1), in: title)
                {
                    return Int(title[numberRange])
                }
            }
        }

        return nil
    }
}

extension DanmakuProvider {
    func _testSyntheticEpisodeID(danDanBangumiID: Int, episodeNumber: Int) -> Int {
        syntheticEpisodeID(danDanBangumiID: danDanBangumiID, episodeNumber: episodeNumber)
    }
}

enum DanmakuEpisodeMatcher {
    static func episodeNumber(for request: PlaybackRequest) -> Int {
        if let parsed = parsedEpisodeNumber(from: request.episode.title), parsed > 0 {
            return parsed
        }
        return request.episode.index + 1
    }

    private static func parsedEpisodeNumber(from title: String) -> Int? {
        let patterns = [
            #"第\s*(\d+)\s*[话話集]"#,
            #"EP?\s*(\d+)"#,
            #"^\s*(\d+)\s*$"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: range),
                    let numberRange = Range(match.range(at: 1), in: title)
                {
                    return Int(title[numberRange])
                }
            }
        }

        return nil
    }
}
