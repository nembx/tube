import Foundation

public struct BangumiRelatedCharacter: Hashable, Sendable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let summary: String
    public let relation: String
    public let images: BangumiImageSet
    public let actors: [BangumiRelatedPerson]

    public init(
        id: Int,
        name: String,
        summary: String,
        relation: String,
        images: BangumiImageSet,
        actors: [BangumiRelatedPerson]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.relation = relation
        self.images = images
        self.actors = actors
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, relation, images, actors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.relation = (try? c.decode(String.self, forKey: .relation)) ?? ""
        self.images = (try? c.decode(BangumiImageSet.self, forKey: .images)) ?? .empty
        self.actors = (try? c.decode([BangumiRelatedPerson].self, forKey: .actors)) ?? []
    }
}

public struct BangumiRelatedPerson: Hashable, Sendable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let relation: String
    public let career: [String]
    public let images: BangumiImageSet
    public let eps: String

    public init(
        id: Int,
        name: String,
        relation: String,
        career: [String],
        images: BangumiImageSet,
        eps: String
    ) {
        self.id = id
        self.name = name
        self.relation = relation
        self.career = career
        self.images = images
        self.eps = eps
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, relation, career, images, eps
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.relation = (try? c.decode(String.self, forKey: .relation)) ?? ""
        self.career = (try? c.decode([String].self, forKey: .career)) ?? []
        self.images = (try? c.decode(BangumiImageSet.self, forKey: .images)) ?? .empty
        self.eps = (try? c.decode(String.self, forKey: .eps)) ?? ""
    }
}

public struct BangumiSubjectComment: Hashable, Sendable, Identifiable {
    public let id: String
    public let authorName: String
    public let avatarURL: URL?
    public let stateLabel: String
    public let ratingLabel: String
    public let publishedAt: String
    public let body: String

    public init(
        id: String,
        authorName: String,
        avatarURL: URL?,
        stateLabel: String,
        ratingLabel: String,
        publishedAt: String,
        body: String
    ) {
        self.id = id
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.stateLabel = stateLabel
        self.ratingLabel = ratingLabel
        self.publishedAt = publishedAt
        self.body = body
    }
}

public struct BangumiSubjectReview: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let authorName: String
    public let avatarURL: URL?
    public let publishedAt: String
    public let replyCount: String
    public let summary: String
    public let url: URL?

    public init(
        id: String,
        title: String,
        authorName: String,
        avatarURL: URL?,
        publishedAt: String,
        replyCount: String,
        summary: String,
        url: URL?
    ) {
        self.id = id
        self.title = title
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.publishedAt = publishedAt
        self.replyCount = replyCount
        self.summary = summary
        self.url = url
    }
}
