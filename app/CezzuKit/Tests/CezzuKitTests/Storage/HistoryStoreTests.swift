import Foundation
import SwiftData
import Testing
@testable import CezzuKit

/// 注意：HistoryStore 依赖 SwiftData `ModelContainer`。在 `swift test` CLI 进程下，
/// SwiftData 的 @MainActor 隔离与 swift-testing 1.x 的并发调度有 SIGTRAP 兼容性 bug
/// （v1 在 macOS 26.0/26.4 上复现）。这些 case 必须在 Xcode test target 里跑 ——
/// 因为那里有完整的 NSApplication 主线程上下文。CLI 跑同样的代码会 crash。
@Suite(
    "HistoryStore",
    .disabled("SwiftData ModelContainer crashes under swift-testing CLI runner; re-enable in Xcode test target")
)
@MainActor
struct HistoryStoreTests {

    private func makeStore() throws -> HistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WatchHistoryEntry.self,
            configurations: config
        )
        return HistoryStore(context: container.mainContext)
    }

    @Test("recordPlaybackStart inserts an entry")
    func recordStart() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        #expect(store.recent.count == 1)
        #expect(store.recent.first?.bangumiTitle == "孤独摇滚")
        #expect(store.recent.first?.lastPositionMs == 0)
    }

    @Test("updateProgress moves the position")
    func updateProgress() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        let url = URL(string: "https://example.com/anime/1")!
        try store.updateProgress(detailURL: url, positionMs: 754_000)
        let entry = try store.entry(forDetailURL: url)
        #expect(entry?.lastPositionMs == 754_000)
    }

    @Test("same bangumi from different sources collapses to one history row")
    func sameBangumiDifferentSourcesCollapse() throws {
        let store = try makeStore()
        let base = makeRequest(ruleName: "xfdmneo", detailPath: "xfdm/1")
        try store.recordPlaybackStart(request: base)
        try store.recordPlaybackStart(request: makeRequest(ruleName: "TvTFun", detailPath: "tvt/1"))
        try store.recordPlaybackStart(request: makeRequest(ruleName: "baimao", detailPath: "bai/1"))

        #expect(store.recent.count == 1)
        #expect(store.recent.first?.bangumiTitle == "孤独摇滚")
        #expect(store.recent.first?.ruleName == "baimao")
        #expect(store.recent.first?.detailURLString == "https://example.com/bai/1")
    }

    @Test("updateProgress by request merges title identity and can set frame cover")
    func updateProgressByRequestSetsCover() throws {
        let store = try makeStore()
        let request = makeRequest(ruleName: "demo", detailPath: "anime/1")
        try store.recordPlaybackStart(request: request)
        try store.updateProgress(
            request: request,
            positionMs: 16_000,
            coverURLString: "file:///tmp/frame.jpg"
        )
        #expect(store.recent.count == 1)
        #expect(store.recent.first?.lastPositionMs == 16_000)
        #expect(store.recent.first?.coverURLString == "file:///tmp/frame.jpg")
    }

    @Test("条目号跟着历史一起存下来，合成条目不会把它冲掉")
    func recordKeepsSubjectID() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        #expect(store.recent.first?.subjectID == 1)

        // 从「继续观看」再进一次：这次带的是 id 为 0 的合成条目。
        let url = URL(string: "https://example.com/anime/1")!
        let hint = HistoryResumeHint(
            bangumiTitle: "孤独摇滚",
            coverURLString: "file:///tmp/frame.jpg",
            detailURL: url,
            ruleName: "demo",
            episodeIndex: 0,
            episodeTitle: "第 1 集",
            positionMs: 0
        )
        var resumed = makeRequest()
        resumed = PlaybackRequest(
            anime: resumed.anime,
            roadIndex: resumed.roadIndex,
            episodeIndex: resumed.episodeIndex,
            rule: resumed.rule,
            item: hint.item
        )
        try store.updateProgress(request: resumed, positionMs: 5_000)

        #expect(store.recent.first?.subjectID == 1)
    }

    @Test("delete drops the entry from continueWatching")
    func deleteRemovesFromContinueWatching() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest(ruleName: "demo", detailPath: "anime/1"))
        let entry = try #require(store.continueWatching.first)
        try store.delete(entry)
        #expect(store.continueWatching.isEmpty)
        #expect(store.recent.isEmpty)
    }

    @Test("clearAll empties the list")
    func clearAll() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        try store.clearAll()
        #expect(store.recent.isEmpty)
    }

    private func makeRequest(
        ruleName: String = "demo",
        detailPath: String = "anime/1"
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
        let road = EpisodeRoad(
            index: 0,
            label: "线路 1",
            episodes: [
                Episode(title: "第 1 集", url: URL(string: "https://example.com/play/1")!, index: 0)
            ]
        )
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://example.com/\(detailPath)")!,
            ruleName: ruleName,
            roads: [road]
        )
        return PlaybackRequest(anime: detail, roadIndex: 0, episodeIndex: 0, rule: rule)
    }
}

/// `subjectID(for:)` 是纯函数，不碰 SwiftData，所以可以在 CLI 里跑。
@Suite("HistoryStore subject id")
struct HistoryStoreSubjectIDTests {
    private static func request(itemID: Int?) -> PlaybackRequest {
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://example.com/anime/1")!,
            ruleName: "demo",
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://play.example/1")!, index: 0)
                    ]
                )
            ]
        )
        let item = itemID.map {
            BangumiItem(
                id: $0, name: "Bocchi", nameCn: "孤独摇滚", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            )
        }
        return PlaybackRequest(
            anime: detail,
            roadIndex: 0,
            episodeIndex: 0,
            rule: CezzuRule(
                api: "0.1.0", type: "vod", name: "demo", version: "1",
                muliSources: false, useWebview: false, useNativePlayer: false, userAgent: "",
                baseURL: "https://example.com", searchURL: "https://example.com/s?wd=@keyword",
                searchList: "//a", searchName: ".", searchResult: "@href",
                chapterRoads: "//div", chapterResult: "//a",
                usePost: false, useLegacyParser: false, adBlocker: false, referer: "",
                antiCrawlerConfig: nil
            ),
            item: item
        )
    }

    @Test("真条目给出条目号")
    func realSubject() {
        #expect(HistoryStore.subjectID(for: Self.request(itemID: 547_888)) == 547_888)
    }

    @Test("合成条目和没有条目的请求都返回 nil，好让已存下的号留着")
    func synthesizedSubject() {
        #expect(HistoryStore.subjectID(for: Self.request(itemID: 0)) == nil)
        #expect(HistoryStore.subjectID(for: Self.request(itemID: nil)) == nil)
    }
}
