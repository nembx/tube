import Foundation
import Testing
@testable import TubeKit

@Suite("PlayerDanmakuController", .serialized)
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

    @MainActor
    @Test("屏蔽词立即清理已有弹幕并过滤后续弹幕，删除后再次播放可恢复")
    func updatesBlockedComments() async throws {
        resetDanmakuKeys()
        defer { resetDanmakuKeys() }
        PlaybackSettings.enableDanmaku = true
        let suiteName = "PlayerDanmakuControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = FakeDanmakuProvider(result: .success([
            DanmakuComment(text: "SPOILER 内容", time: 1, type: 1, colorRGB: 16_777_215, source: "test"),
            DanmakuComment(text: "正常弹幕", time: 1, type: 1, colorRGB: 16_777_215, source: "test"),
            DanmakuComment(text: "后续 spoiler", time: 2, type: 1, colorRGB: 16_777_215, source: "test"),
        ]))
        let controller = PlayerDanmakuController(provider: provider, defaults: defaults)
        await controller.prepare(for: makeRequest())
        let viewport = CGSize(width: 800, height: 450)
        controller.update(currentTime: 1, viewportSize: viewport, playbackRate: 1)
        #expect(controller.activeComments.count == 2)

        defaults.set("ｓｐｏｉｌｅｒ", forKey: DanmakuBlocklist.storageKey)
        controller.refreshBlocklist()
        #expect(controller.activeComments.map(\.comment.text) == ["正常弹幕"])
        controller.update(currentTime: 2, viewportSize: viewport, playbackRate: 1)
        #expect(controller.activeComments.map(\.comment.text) == ["正常弹幕"])
        #expect(controller.comments.count == 3)

        defaults.removeObject(forKey: DanmakuBlocklist.storageKey)
        controller.update(currentTime: 0, viewportSize: viewport, playbackRate: 1)
        controller.update(currentTime: 1, viewportSize: viewport, playbackRate: 1)
        #expect(controller.activeComments.count == 2)
        #expect(await provider.fetchCount() == 1)
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
            rule: TubeRule(
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
