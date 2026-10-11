import Testing

@testable import TubeKit

@Suite("BangumiEpisode")
struct BangumiEpisodeTests {
    private static func episode(id: Int, ep: Double, sort: Double? = nil) -> BangumiEpisode {
        BangumiEpisode(
            id: id,
            ep: ep,
            sort: sort ?? ep,
            name: "ep \(ep)",
            nameCn: "",
            airDate: "",
            commentCount: 0
        )
    }

    @Test("播放器的第 N 集按 ep 号对到 bgm 的同一集")
    func matchesByEpisodeNumber() {
        let episodes = [Self.episode(id: 10, ep: 1), Self.episode(id: 11, ep: 2)]

        #expect(BangumiEpisode.match(episodeIndex: 1, in: episodes)?.id == 11)
    }

    @Test("ep 号缺失时退回 sort 号")
    func matchesBySortWhenEpMissing() {
        let episodes = [
            Self.episode(id: 10, ep: 0, sort: 1),
            Self.episode(id: 11, ep: 0, sort: 2),
        ]

        #expect(BangumiEpisode.match(episodeIndex: 1, in: episodes)?.id == 11)
    }

    @Test("集号完全对不上时按位置兜底")
    func fallsBackToPosition() {
        let episodes = [Self.episode(id: 10, ep: 101), Self.episode(id: 11, ep: 102)]

        #expect(BangumiEpisode.match(episodeIndex: 1, in: episodes)?.id == 11)
    }

    @Test("越界和空列表都拿不到集，不能崩")
    func matchOutOfRange() {
        #expect(BangumiEpisode.match(episodeIndex: 0, in: []) == nil)
        #expect(BangumiEpisode.match(episodeIndex: 5, in: [Self.episode(id: 10, ep: 1)]) == nil)
        #expect(BangumiEpisode.match(episodeIndex: -1, in: [Self.episode(id: 10, ep: 1)]) == nil)
    }
}
