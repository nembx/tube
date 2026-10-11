import Foundation

/// 一集（episode），属于某条线路（road）。
public struct Episode: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var index: Int

    public init(id: UUID = UUID(), title: String, url: URL, index: Int) {
        self.id = id
        self.title = title
        self.url = url
        self.index = index
    }
}

/// 一条"线路"（road / mirror line）。当规则的 `muliSources = true` 时，
/// 同一部番剧的详情页可能匹配多个 road，每个 road 是同一集的一组备用源。
public struct EpisodeRoad: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var index: Int
    public var label: String  // 人类可读名（"线路 1"、"线路 2"），由 UI 兜底
    public var episodes: [Episode]

    public init(id: UUID = UUID(), index: Int, label: String, episodes: [Episode]) {
        self.id = id
        self.index = index
        self.label = label
        self.episodes = episodes
    }
}

/// 一部番剧的详情快照（从详情页抓出来的数据），主要用作 5 个屏幕之间传递的载体。
public struct AnimeDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: URL { detailURL }
    public var title: String
    public var detailURL: URL
    public var ruleName: String
    public var roads: [EpisodeRoad]

    public init(title: String, detailURL: URL, ruleName: String, roads: [EpisodeRoad]) {
        self.title = title
        self.detailURL = detailURL
        self.ruleName = ruleName
        self.roads = roads
    }
}
