import Foundation
import Testing
@testable import TubeKit

@Suite("PlayerDetailModel")
@MainActor
struct PlayerDetailModelTests {
    struct FakeSourceSearchCoordinator: SourceSearchCoordinating {
        let updates: [String: [SearchCoordinator.Update]]

        func search(
            keyword: String,
            rules: [TubeRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            let updates = updates[keyword] ?? [.finished]
            return AsyncStream { continuation in
                for update in updates {
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }

        func searchAll(
            keywords: [String],
            rules: [TubeRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                for keyword in keywords {
                    for update in updates[keyword] ?? [] {
                        continuation.yield(update)
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }

    struct FakeRuleEngine: RuleEngine {
        let episodesByRuleName: [String: [EpisodeRoad]]

        func search(_ keyword: String, with rule: TubeRule) async throws -> [SearchResult] {
            []
        }

        func fetchEpisodes(detailURL: URL, with rule: TubeRule) async throws -> [EpisodeRoad] {
            episodesByRuleName[rule.name] ?? []
        }
    }

    @Test("sync keeps current request available before remote source search")
    func syncSeedsCurrentSource() throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 1)
        let model = PlayerDetailModel(
            currentRequest: request,
            rules: [Self.makeRule(name: "AGE")]
        )

        #expect(model.sources.map(\.ruleName) == ["AGE"])
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.selectedRoadIndex == 0)

        let selected = try #require(model.playbackRequest(episodeIndex: 1))
        #expect(selected.episode.title == "第 2 集")
    }

    @Test("loadSourcesIfNeeded adds searchable alternate sources and fetches their episodes")
    func loadFindsAlternateSources() async throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 0)
        let model = PlayerDetailModel(
            currentRequest: request,
            rules: [
                Self.makeRule(name: "AGE"),
                Self.makeRule(name: "AnFuns"),
            ],
            searchCoordinator: FakeSourceSearchCoordinator(
                updates: [
                    "孤独摇滚": [
                        .ruleResults(
                            name: "AnFuns",
                            results: [
                                SearchResult(
                                    title: "孤独摇滚",
                                    detailURL: URL(string: "https://anfuns.example/bocchi")!,
                                    ruleName: "AnFuns"
                                )
                            ]
                        ),
                        .finished,
                    ]
                ]
            ),
            engine: FakeRuleEngine(
                episodesByRuleName: [
                    "AnFuns": [
                        EpisodeRoad(
                            index: 0,
                            label: "线路 A",
                            episodes: [
                                Episode(title: "第 1 集", url: URL(string: "https://play.example/anfuns-1")!, index: 0)
                            ]
                        )
                    ]
                ]
            )
        )

        await model.loadSourcesIfNeeded()
        #expect(model.sources.map(\.ruleName) == ["AGE", "AnFuns"])

        // 源的身份是「规则 + 详情页」，一条规则可以贡献多个条目，所以不能拿规则名当 id
        let anfuns = try #require(model.sources.first(where: { $0.ruleName == "AnFuns" }))
        await model.selectSource(anfuns.id)
        let selected = try #require(model.playbackRequest(episodeIndex: 0))
        #expect(selected.rule.name == "AnFuns")
        #expect(selected.anime.detailURL.absoluteString == "https://anfuns.example/bocchi")
    }

    // MARK: - 分集评论

    @Test("评论拉的是当前正在看的那一集")
    func commentsFollowCurrentEpisode() async throws {
        let api = FakeBangumiAPI(
            episodes: [
                Self.bangumiEpisode(id: 900, ep: 1, title: "第一集"),
                Self.bangumiEpisode(id: 901, ep: 2, title: "第二集"),
            ],
            commentsByEpisodeID: [901: [Self.comment(id: "p1", body: "ep2 好看")]]
        )
        let model = PlayerDetailModel(
            currentRequest: Self.makeRequest(ruleName: "AGE", episodeIndex: 1),
            rules: [Self.makeRule(name: "AGE")],
            api: api
        )

        await model.loadCommentsIfNeeded()

        guard case .loaded(let comments) = model.commentsState else {
            Issue.record("评论没有加载出来：\(model.commentsState)")
            return
        }
        #expect(comments.map(\.body) == ["ep2 好看"])
        #expect(api.episodeCommentRequests == [901])
    }

    @Test("同一集不会重复拉，换集才重新拉")
    func commentsReloadOnlyWhenEpisodeChanges() async throws {
        let api = FakeBangumiAPI(
            episodes: [
                Self.bangumiEpisode(id: 900, ep: 1, title: "第一集"),
                Self.bangumiEpisode(id: 901, ep: 2, title: "第二集"),
            ],
            commentsByEpisodeID: [900: [], 901: []]
        )
        let model = PlayerDetailModel(
            currentRequest: Self.makeRequest(ruleName: "AGE", episodeIndex: 0),
            rules: [Self.makeRule(name: "AGE")],
            api: api
        )

        await model.loadCommentsIfNeeded()
        await model.loadCommentsIfNeeded()
        #expect(api.episodeCommentRequests == [900])

        model.syncCurrentRequest(
            Self.makeRequest(ruleName: "AGE", episodeIndex: 1),
            rules: [Self.makeRule(name: "AGE")]
        )
        await model.loadCommentsIfNeeded()

        #expect(api.episodeCommentRequests == [900, 901])
        // 分集表只拉一次，换集只换 episode id。
        #expect(api.episodeListRequests == 1)
    }

    @Test("顶部简介拿的是当前这一集的标题、时长和梗概")
    func episodeInfoDescribesCurrentEpisode() async throws {
        let api = FakeBangumiAPI(
            episodes: [
                Self.bangumiEpisode(id: 900, ep: 1, title: "第一集"),
                Self.bangumiEpisode(
                    id: 901, ep: 2, title: "第二集", duration: "00:23:40", desc: "梗概"
                ),
            ],
            commentsByEpisodeID: [:]
        )
        let model = PlayerDetailModel(
            currentRequest: Self.makeRequest(ruleName: "AGE", episodeIndex: 1),
            rules: [Self.makeRule(name: "AGE")],
            api: api
        )

        await model.loadEpisodeInfoIfNeeded()

        guard case .loaded(let episode) = model.episodeInfoState else {
            Issue.record("简介没有加载出来：\(model.episodeInfoState)")
            return
        }
        #expect(episode.displayHeadline == "ep.2 第二集")
        #expect(episode.duration == "00:23:40")
        #expect(episode.desc == "梗概")
        // 简介和评论共用同一份分集表，不该各拉一次。
        await model.loadCommentsIfNeeded()
        #expect(api.episodeListRequests == 1)
    }

    /// 回归：从「继续观看」进播放页时条目是合成的，id 为 0。
    /// 拿它去请求 `/v0/episodes` 会被 bgm 直接判 400 —— 得先拦下来。
    @Test("条目号为 0 时不发请求，直接说明拿不到")
    func zeroSubjectIDNeverHitsTheAPI() async throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 0)
        let synthesized = PlaybackRequest(
            anime: request.anime,
            roadIndex: 0,
            episodeIndex: 0,
            rule: request.rule,
            item: HistoryResumeHint(
                bangumiTitle: "孤独摇滚",
                coverURLString: nil,
                detailURL: request.anime.detailURL,
                ruleName: "AGE",
                episodeIndex: 0,
                episodeTitle: "第 1 集",
                positionMs: 0
            ).item
        )
        let api = FakeBangumiAPI(episodes: [], commentsByEpisodeID: [:])
        let model = PlayerDetailModel(
            currentRequest: synthesized,
            rules: [Self.makeRule(name: "AGE")],
            api: api
        )

        await model.loadEpisodeInfoIfNeeded()
        await model.loadCommentsIfNeeded()

        guard case .unavailable = model.episodeInfoState else {
            Issue.record("合成条目应该是 unavailable：\(model.episodeInfoState)")
            return
        }
        #expect(api.episodeListRequests == 0)
        #expect(api.episodeCommentRequests.isEmpty)
    }

    @Test("没有 bangumi 条目时说明拿不到，而不是报错")
    func commentsUnavailableWithoutSubject() async throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 0)
        let orphan = PlaybackRequest(
            anime: request.anime,
            roadIndex: 0,
            episodeIndex: 0,
            rule: request.rule,
            item: nil
        )
        let model = PlayerDetailModel(
            currentRequest: orphan,
            rules: [Self.makeRule(name: "AGE")],
            api: FakeBangumiAPI(episodes: [], commentsByEpisodeID: [:])
        )

        await model.loadCommentsIfNeeded()

        guard case .unavailable = model.commentsState else {
            Issue.record("没有条目时应该是 unavailable：\(model.commentsState)")
            return
        }
    }

    @Test("拉失败之后还能重试")
    func commentsCanBeRetriedAfterFailure() async throws {
        let api = FakeBangumiAPI(
            episodes: [Self.bangumiEpisode(id: 900, ep: 1, title: "第一集")],
            commentsByEpisodeID: [:],
            failEpisodeComments: true
        )
        let model = PlayerDetailModel(
            currentRequest: Self.makeRequest(ruleName: "AGE", episodeIndex: 0),
            rules: [Self.makeRule(name: "AGE")],
            api: api
        )

        await model.loadCommentsIfNeeded()
        guard case .failed = model.commentsState else {
            Issue.record("接口失败时应该是 failed：\(model.commentsState)")
            return
        }

        api.failEpisodeComments = false
        api.commentsByEpisodeID[900] = [Self.comment(id: "p1", body: "重试成功")]
        await model.reloadComments()

        guard case .loaded(let comments) = model.commentsState else {
            Issue.record("重试后应该加载出来：\(model.commentsState)")
            return
        }
        #expect(comments.map(\.body) == ["重试成功"])
    }

    private static func bangumiEpisode(
        id: Int,
        ep: Double,
        title: String,
        duration: String = "",
        desc: String = ""
    ) -> BangumiEpisode {
        BangumiEpisode(
            id: id,
            ep: ep,
            sort: ep,
            name: title,
            nameCn: title,
            airDate: "",
            duration: duration,
            desc: desc,
            commentCount: 0
        )
    }

    private static func comment(id: String, body: String) -> BangumiEpisodeComment {
        BangumiEpisodeComment(
            id: id,
            floor: "#1",
            authorName: "someone",
            avatarURL: nil,
            publishedAt: "2026-9-3 12:00",
            body: body
        )
    }

    private static func makeRequest(ruleName: String, episodeIndex: Int) -> PlaybackRequest {
        let item = BangumiItem(
            id: 1,
            name: "Bocchi the Rock!",
            nameCn: "孤独摇滚",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://age.example/bocchi")!,
            ruleName: ruleName,
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://play.example/1")!, index: 0),
                        Episode(title: "第 2 集", url: URL(string: "https://play.example/2")!, index: 1),
                    ]
                )
            ]
        )

        return PlaybackRequest(
            anime: detail,
            roadIndex: 0,
            episodeIndex: episodeIndex,
            rule: makeRule(name: ruleName),
            item: item
        )
    }

    /// 只实现评论这条链路要用的两个方法，其余按协议给空实现。
    @MainActor
    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        let episodes: [BangumiEpisode]
        var commentsByEpisodeID: [Int: [BangumiEpisodeComment]]
        var failEpisodeComments: Bool
        private(set) var episodeListRequests = 0
        private(set) var episodeCommentRequests: [Int] = []

        init(
            episodes: [BangumiEpisode],
            commentsByEpisodeID: [Int: [BangumiEpisodeComment]],
            failEpisodeComments: Bool = false
        ) {
            self.episodes = episodes
            self.commentsByEpisodeID = commentsByEpisodeID
            self.failEpisodeComments = failEpisodeComments
        }

        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] {
            episodeListRequests += 1
            return episodes
        }

        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] {
            episodeCommentRequests.append(episodeID)
            if failEpisodeComments { throw BangumiAPIError.http(status: 500) }
            return commentsByEpisodeID[episodeID] ?? []
        }

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            throw BangumiAPIError.http(status: 404)
        }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
    }

    private static func makeRule(name: String) -> TubeRule {
        TubeRule(
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
