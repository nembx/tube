import Foundation

/// Bangumi 收藏状态（`/v0/users/-/collections/{subject_id}` 的 `type`）。
///
/// 数值与 bgm 官方 OpenAPI 一致，不能改 —— 直接进请求体。
public enum BangumiCollectionType: Int, CaseIterable, Hashable, Sendable, Codable {
    case wish = 1
    case collect = 2
    case doing = 3
    case onHold = 4
    case dropped = 5

    /// 中文名，与 bgm 网页端一致。
    public var label: String {
        switch self {
        case .wish: return "想看"
        case .collect: return "看过"
        case .doing: return "在看"
        case .onHold: return "搁置"
        case .dropped: return "抛弃"
        }
    }

    /// 详情页状态胶囊用的 SF Symbol。
    public var systemImage: String {
        switch self {
        case .wish: return "bookmark"
        case .collect: return "checkmark.circle.fill"
        case .doing: return "play.circle.fill"
        case .onHold: return "pause.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

/// 单集观看状态（`episode collection` 的 `type`）。
public enum BangumiEpisodeCollectionType: Int, CaseIterable, Hashable, Sendable, Codable {
    case none = 0
    case wish = 1
    case done = 2
    case dropped = 3

    public var label: String {
        switch self {
        case .none: return "未看"
        case .wish: return "想看"
        case .done: return "看过"
        case .dropped: return "抛弃"
        }
    }

    /// 「已看」在本 App 里等价于 bgm 的 done。播放到片尾就按这个写。
    public var isWatched: Bool { self == .done }
}

/// 用户对某个条目的收藏。`GET /v0/users/{username}/collections` 与
/// `GET /v0/users/-/collections/{subject_id}` 的返回体。
public struct BangumiUserCollection: Hashable, Sendable, Identifiable, Codable {
    public let subjectID: Int
    public let type: BangumiCollectionType
    /// 看到第几集（正片序号）。
    public let epStatus: Int
    public let volStatus: Int
    public let rate: Int
    public let comment: String
    public let isPrivate: Bool
    public let tags: [String]
    public let updatedAt: String
    /// 列表接口带 `subject`；单条接口也带。缺省时由调用方用本地条目兜底。
    public let subject: BangumiItem?

    public var id: Int { subjectID }

    public init(
        subjectID: Int,
        type: BangumiCollectionType,
        epStatus: Int = 0,
        volStatus: Int = 0,
        rate: Int = 0,
        comment: String = "",
        isPrivate: Bool = false,
        tags: [String] = [],
        updatedAt: String = "",
        subject: BangumiItem? = nil
    ) {
        self.subjectID = subjectID
        self.type = type
        self.epStatus = epStatus
        self.volStatus = volStatus
        self.rate = rate
        self.comment = comment
        self.isPrivate = isPrivate
        self.tags = tags
        self.updatedAt = updatedAt
        self.subject = subject
    }

    private enum CodingKeys: String, CodingKey {
        case subjectID = "subject_id"
        case type
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case rate
        case comment
        case isPrivate = "private"
        case tags
        case updatedAt = "updated_at"
        case subject
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.subjectID = (try? c.decode(Int.self, forKey: .subjectID)) ?? 0
        let rawType = (try? c.decode(Int.self, forKey: .type)) ?? 0
        self.type = BangumiCollectionType(rawValue: rawType) ?? .wish
        self.epStatus = (try? c.decode(Int.self, forKey: .epStatus)) ?? 0
        self.volStatus = (try? c.decode(Int.self, forKey: .volStatus)) ?? 0
        self.rate = (try? c.decode(Int.self, forKey: .rate)) ?? 0
        self.comment = (try? c.decode(String.self, forKey: .comment)) ?? ""
        self.isPrivate = (try? c.decode(Bool.self, forKey: .isPrivate)) ?? false
        self.tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        self.updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        self.subject = try? c.decode(BangumiItem.self, forKey: .subject)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subjectID, forKey: .subjectID)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(epStatus, forKey: .epStatus)
        try c.encode(volStatus, forKey: .volStatus)
        try c.encode(rate, forKey: .rate)
        try c.encode(comment, forKey: .comment)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(tags, forKey: .tags)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(subject, forKey: .subject)
    }
}

extension BangumiUserCollection {
    /// 只改状态，其余字段原样带过去。
    public func withType(_ type: BangumiCollectionType) -> BangumiUserCollection {
        BangumiUserCollection(
            subjectID: subjectID, type: type, epStatus: epStatus, volStatus: volStatus,
            rate: rate, comment: comment, isPrivate: isPrivate, tags: tags,
            updatedAt: updatedAt, subject: subject
        )
    }

    /// 只改已看集数。
    public func withEpStatus(_ epStatus: Int) -> BangumiUserCollection {
        BangumiUserCollection(
            subjectID: subjectID, type: type, epStatus: epStatus, volStatus: volStatus,
            rate: rate, comment: comment, isPrivate: isPrivate, tags: tags,
            updatedAt: updatedAt, subject: subject
        )
    }
}

/// 单集的收藏状态。`GET /v0/users/-/collections/{subject_id}/episodes` 的 data 元素。
public struct BangumiUserEpisodeCollection: Hashable, Sendable, Decodable {
    public let episode: BangumiEpisode
    public let type: BangumiEpisodeCollectionType

    public init(episode: BangumiEpisode, type: BangumiEpisodeCollectionType) {
        self.episode = episode
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case episode
        case type
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.episode = try c.decode(BangumiEpisode.self, forKey: .episode)
        let raw = (try? c.decode(Int.self, forKey: .type)) ?? 0
        self.type = BangumiEpisodeCollectionType(rawValue: raw) ?? .none
    }
}

/// 写收藏时的请求体。`type` 必填，其余按需带。
public struct BangumiCollectionUpdate: Hashable, Sendable, Codable {
    public var type: BangumiCollectionType
    public var epStatus: Int?
    public var volStatus: Int?
    public var rate: Int?
    public var comment: String?
    public var isPrivate: Bool?
    public var tags: [String]?

    public init(
        type: BangumiCollectionType,
        epStatus: Int? = nil,
        volStatus: Int? = nil,
        rate: Int? = nil,
        comment: String? = nil,
        isPrivate: Bool? = nil,
        tags: [String]? = nil
    ) {
        self.type = type
        self.epStatus = epStatus
        self.volStatus = volStatus
        self.rate = rate
        self.comment = comment
        self.isPrivate = isPrivate
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case rate
        case comment
        case isPrivate = "private"
        case tags
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type.rawValue, forKey: .type)
        try c.encodeIfPresent(epStatus, forKey: .epStatus)
        try c.encodeIfPresent(volStatus, forKey: .volStatus)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(tags, forKey: .tags)
    }
}
