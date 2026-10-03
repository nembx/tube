import Foundation
import Testing
@testable import CezzuKit

@Suite("PlaybackRequest")
struct PlaybackRequestTests {
    @Test("exposes previous and next episode requests on the same road")
    func neighborEpisodeRequests() throws {
        let request = Self.makeRequest(episodeIndex: 1)

        let previous = try #require(request.previousEpisodeRequest)
        let next = try #require(request.nextEpisodeRequest)

        #expect(previous.episodeIndex == 0)
        #expect(previous.episode.title == "第 1 集")
        #expect(next.episodeIndex == 2)
        #expect(next.episode.title == "第 3 集")
    }

    @Test("returns nil at both road boundaries")
    func neighborRequestsStopAtEdges() {
        let first = Self.makeRequest(episodeIndex: 0)
        let last = Self.makeRequest(episodeIndex: 2)

        #expect(first.previousEpisodeRequest == nil)
        #expect(first.hasPreviousEpisode == false)
        #expect(last.nextEpisodeRequest == nil)
        #expect(last.hasNextEpisode == false)
    }

    private static func makeRequest(episodeIndex: Int) -> PlaybackRequest {
        let detail = AnimeDetail(
            title: "测试番剧",
            detailURL: URL(string: "https://example.com/detail")!,
            ruleName: "Test",
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://example.com/1")!, index: 0),
                        Episode(title: "第 2 集", url: URL(string: "https://example.com/2")!, index: 1),
                        Episode(title: "第 3 集", url: URL(string: "https://example.com/3")!, index: 2),
                    ]
                )
            ]
        )

        return PlaybackRequest(
            anime: detail,
            roadIndex: 0,
            episodeIndex: episodeIndex,
            rule: makeRule(name: "Test")
        )
    }

    private static func makeRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "0.1.0",
            type: "vod",
            name: name,
            version: "1",
            muliSources: false,
            useWebview: false,
            useNativePlayer: false,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//a",
            searchName: ".",
            searchResult: "@href",
            chapterRoads: "//div[@class='road']",
            chapterResult: "//a",
            usePost: false,
            useLegacyParser: false,
            adBlocker: false,
            referer: "",
            antiCrawlerConfig: nil
        )
    }
}
