import Foundation
import Testing
@testable import CezzuKit

@Suite("PlayerDanmakuController")
struct PlayerDanmakuControllerTests {
    @MainActor
    @Test("prepare reloads same request after danmaku is re-enabled")
    func prepareReloadsAfterReenable() async {
        resetDanmakuKeys()
        defer { resetDanmakuKeys() }

        let provider = FakeDanmakuProvider(
            result: .success([
                DanmakuComment(
                    text: "测试弹幕",
                    time: 1.5,
                    type: 1,
                    colorRGB: 16_777_215,
                    source: "DanDanPlay"
                )
            ])
        )
        let controller = PlayerDanmakuController(provider: provider)
        let request = makeRequest()

        PlaybackSettings.enableDanmaku = false
        await controller.prepare(for: request)
        #expect(controller.comments.isEmpty)
        #expect(await provider.fetchCount() == 0)

        PlaybackSettings.enableDanmaku = true
        await controller.prepare(for: request)
        #expect(await provider.fetchCount() == 1)
        #expect(controller.comments.count == 1)
    }

    private func makeRequest() -> PlaybackRequest {
        PlaybackRequest(
            anime: AnimeDetail(
                title: "测试番剧",
                detailURL: URL(string: "https://example.com/detail")!,
                ruleName: "rule",
                roads: [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第1集", url: URL(string: "https://example.com/ep1")!, index: 0)
                        ]
                    )
                ]
            ),
            roadIndex: 0,
            episodeIndex: 0,
            rule: CezzuRule(
                api: "0.1.0",
                type: "vod",
                name: "rule",
                version: "1",
                muliSources: false,
                useWebview: false,
                useNativePlayer: false,
                userAgent: "",
                baseURL: "https://example.com",
                searchURL: "https://example.com/search?wd=@keyword",
                searchList: "//a",
                searchName: ".",
                searchResult: ".",
                chapterRoads: "//div",
                chapterResult: ".//a"
            ),
            item: BangumiItem(
                id: 1,
                name: "test",
                nameCn: "测试番剧",
                summary: "",
                airDate: "",
                rank: 0,
                ratingScore: 0,
                images: .empty,
                tags: []
            )
        )
    }

    private func resetDanmakuKeys() {
        let defaults = UserDefaults.standard
        for key in [
            PlaybackSettings.enableDanmakuKey,
            PlaybackSettings.showTopDanmakuKey,
            PlaybackSettings.showBottomDanmakuKey,
            PlaybackSettings.showScrollDanmakuKey,
            PlaybackSettings.followPlaybackRateDanmakuKey,
            PlaybackSettings.danmakuFontSizeKey,
            PlaybackSettings.danmakuOpacityKey,
            PlaybackSettings.danmakuAreaKey,
            PlaybackSettings.danmakuDurationKey,
            PlaybackSettings.danmakuLineHeightKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }
    // MARK: - 暂停时的速率

    @Test("暂停时沿用停之前的速率，弹幕位置不跳")
    func stabilizedRateHoldsThroughPause() {
        let playing = DanmakuPlaybackRate.stabilized(2.0, previous: 1.0)
        #expect(playing == 2.0)

        let paused = DanmakuPlaybackRate.stabilized(0, previous: playing)
        #expect(paused == 2.0)

        let resumed = DanmakuPlaybackRate.stabilized(2.0, previous: paused)
        #expect(resumed == 2.0)
    }

    @Test("负速率也算停下，同样沿用上一次的值")
    func stabilizedRateIgnoresNonPositiveRate() {
        #expect(DanmakuPlaybackRate.stabilized(-1, previous: 1.5) == 1.5)
        #expect(DanmakuPlaybackRate.stabilized(0, previous: DanmakuPlaybackRate.fallback) == 1.0)
    }
}

private actor FakeDanmakuProvider: DanmakuProviderProtocol {
    private let result: Result<[DanmakuComment], Error>
    private var calls: Int = 0

    init(result: Result<[DanmakuComment], Error>) {
        self.result = result
    }

    func fetchDanmaku(for request: PlaybackRequest) async throws -> [DanmakuComment] {
        calls += 1
        return try result.get()
    }

    func fetchCount() -> Int {
        calls
    }
}
