import Foundation

/// 番剧角色 —— `/v0/subjects/{id}/characters` 返回的元素。
public struct BangumiCharacter: Hashable, Sendable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let relation: String        // "主角" / "配角" / "客串"
    public let images: BangumiImageSet
    public let actors: [BangumiActor]

    public init(
        id: Int,
        name: String,
        relation: String,
        images: BangumiImageSet,
        actors: [BangumiActor]
    ) {
        self.id = id
        self.name = name
        self.relation = relation
        self.images = images
        self.actors = actors
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, relation, images, actors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.relation = (try? c.decode(String.self, forKey: .relation)) ?? "未知"
        self.images = (try? c.decode(BangumiImageSet.self, forKey: .images)) ?? .empty
        self.actors = (try? c.decode([BangumiActor].self, forKey: .actors)) ?? []
    }
}

/// 配音演员 —— 角色 `actors` 数组里的元素。
public struct BangumiActor: Hashable, Sendable, Identifiable, Decodable {
    public let id: Int
    public let name: String
    public let images: BangumiImageSet

    public init(id: Int, name: String, images: BangumiImageSet) {
        self.id = id
        self.name = name
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, images
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.images = (try? c.decode(BangumiImageSet.self, forKey: .images)) ?? .empty
    }
}

/// 比 BangumiImages 更通用的图集（角色 / 演员 / 制作人员都用这套字段，少一个 common）。
public struct BangumiImageSet: Hashable, Sendable, Decodable {
    public let large: String
    public let medium: String
    public let small: String
    public let grid: String

    public init(large: String, medium: String, small: String, grid: String) {
        self.large = large
        self.medium = medium
        self.small = small
        self.grid = grid
    }

    public static let empty = BangumiImageSet(large: "", medium: "", small: "", grid: "")

    public var best: String {
        for c in [large, medium, grid, small] where !c.isEmpty { return c }
        return ""
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.large = (try? c.decode(String.self, forKey: .large)) ?? ""
        self.medium = (try? c.decode(String.self, forKey: .medium)) ?? ""
        self.small = (try? c.decode(String.self, forKey: .small)) ?? ""
        self.grid = (try? c.decode(String.self, forKey: .grid)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case large, medium, small, grid
    }
}
