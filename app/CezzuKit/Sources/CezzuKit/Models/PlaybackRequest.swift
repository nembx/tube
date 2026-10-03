import Foundation

/// 启动播放需要的全部信息。从 EpisodeListView 流到 PlayerView 的载体。
public struct PlaybackRequest: Codable, Hashable, Sendable {
    public var anime: AnimeDetail
    public var roadIndex: Int
    public var episodeIndex: Int
    public var rule: CezzuRule
    public var item: BangumiItem?

    public init(
        anime: AnimeDetail,
        roadIndex: Int,
        episodeIndex: Int,
        rule: CezzuRule,
        item: BangumiItem? = nil
    ) {
        self.anime = anime
        self.roadIndex = roadIndex
        self.episodeIndex = episodeIndex
        self.rule = rule
        self.item = item
    }

    public var episode: Episode {
        anime.roads[roadIndex].episodes[episodeIndex]
    }

    public var hasPreviousEpisode: Bool {
        episodeIndex > 0
    }

    public var hasNextEpisode: Bool {
        episodeIndex + 1 < anime.roads[roadIndex].episodes.count
    }

    public func requestForEpisode(at episodeIndex: Int) -> PlaybackRequest? {
        guard anime.roads.indices.contains(roadIndex) else { return nil }
        let episodes = anime.roads[roadIndex].episodes
        guard episodes.indices.contains(episodeIndex) else { return nil }

        var next = self
        next.episodeIndex = episodeIndex
        return next
    }

    public var previousEpisodeRequest: PlaybackRequest? {
        requestForEpisode(at: episodeIndex - 1)
    }

    public var nextEpisodeRequest: PlaybackRequest? {
        requestForEpisode(at: episodeIndex + 1)
    }
}
