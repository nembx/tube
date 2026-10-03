import Foundation
import Testing
@testable import CezzuKit

@Suite("PlaybackCoordinator")
@MainActor
struct PlaybackCoordinatorTests {

    @Test("resume hint only applies to the same rule road and episode")
    func ingestResumeHintRequiresMatchingRequest() {
        let coordinator = PlaybackCoordinator()
        let entry = WatchHistoryEntry(
            detailURLString: "https://example.com/anime/1",
            bangumiTitle: "孤独摇滚",
            coverURLString: nil,
            ruleName: "demo",
            lastEpisodeIndex: 2,
            lastEpisodeTitle: "第 3 集",
            lastPositionMs: 721_000
        )

        coordinator.ingestResumeHint(entry, for: Self.makeRequest(roadIndex: 1, episodeIndex: 2))
        #expect(coordinator.resumePromptPositionMs == 721_000)

        coordinator.ingestResumeHint(entry, for: Self.makeRequest(roadIndex: 1, episodeIndex: 1))
        #expect(coordinator.resumePromptPositionMs == nil)

        coordinator.ingestResumeHint(entry, for: Self.makeRequest(
            roadIndex: 0,
            episodeIndex: 2,
            episodeTitles: [
                ["第 1 集", "第 2 集", "第 3 集（备用）"],
                ["第 1 集", "第 2 集", "第 3 集"],
            ]
        ))
        #expect(coordinator.resumePromptPositionMs == nil)
    }

    @Test("resume hint ignores mismatched rule names")
    func ingestResumeHintRejectsDifferentRule() {
        let coordinator = PlaybackCoordinator()
        let entry = WatchHistoryEntry(
            detailURLString: "https://example.com/anime/1",
            bangumiTitle: "孤独摇滚",
            coverURLString: nil,
            ruleName: "demo",
            lastEpisodeIndex: 1,
            lastEpisodeTitle: "第 2 集",
            lastPositionMs: 721_000
        )

        coordinator.ingestResumeHint(entry, for: Self.makeRequest(ruleName: "other", roadIndex: 0, episodeIndex: 1))

        #expect(coordinator.resumePromptPositionMs == nil)
    }

    private static func makeRequest(
        ruleName: String = "demo",
        roadIndex: Int,
        episodeIndex: Int,
        episodeTitles: [[String]] = [
            ["第 1 集", "第 2 集", "第 3 集"],
            ["第 1 集", "第 2 集", "第 3 集"],
        ]
    ) -> PlaybackRequest {
        let rule = CezzuRule(
            api: "1",
            type: "anime",
            name: ruleName,
            version: "1.0",
            muliSources: false,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        let roads = [
            EpisodeRoad(
                index: 0,
                label: "线路 1",
                episodes: [
                    Episode(title: episodeTitles[0][0], url: URL(string: "https://example.com/play/1")!, index: 0),
                    Episode(title: episodeTitles[0][1], url: URL(string: "https://example.com/play/2")!, index: 1),
                    Episode(title: episodeTitles[0][2], url: URL(string: "https://example.com/play/3")!, index: 2),
                ]
            ),
            EpisodeRoad(
                index: 1,
                label: "线路 2",
                episodes: [
                    Episode(title: episodeTitles[1][0], url: URL(string: "https://example.com/alt-play/1")!, index: 0),
                    Episode(title: episodeTitles[1][1], url: URL(string: "https://example.com/alt-play/2")!, index: 1),
                    Episode(title: episodeTitles[1][2], url: URL(string: "https://example.com/alt-play/3")!, index: 2),
                ]
            ),
        ]
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://example.com/anime/1")!,
            ruleName: ruleName,
            roads: roads
        )
        return PlaybackRequest(
            anime: detail,
            roadIndex: roadIndex,
            episodeIndex: episodeIndex,
            rule: rule
        )
    }
}
