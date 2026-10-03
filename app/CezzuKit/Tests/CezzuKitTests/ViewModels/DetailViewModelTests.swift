import Foundation
import Testing
@testable import CezzuKit

@Suite("DetailViewModel")
@MainActor
struct DetailViewModelTests {
    actor SearchLoadProbe {
        private(set) var fetchStarted = false
        private(set) var fetchStartedBeforeSearchFinished = false

        func markFetchStarted() {
            fetchStarted = true
        }

        func waitForFetchStarted(timeout: Duration) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            while !fetchStarted, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return fetchStarted
        }

        func recordSearchFinish() {
            fetchStartedBeforeSearchFinished = fetchStarted
        }
    }

    struct FakeSourceSearchCoordinator: SourceSearchCoordinating {
        let updates: [String: [SearchCoordinator.Update]]

        init(updates: [String: [SearchCoordinator.Update]]) {
            self.updates = updates
        }

        func search(
            keyword: String,
            rules: [CezzuRule]
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
            rules: [CezzuRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                let allowedRuleNames = Set(rules.map(\.name))
                for keyword in keywords {
                    for update in updates[keyword] ?? [] {
                        switch update {
                        case .ruleStarted(let name), .ruleResults(let name, _):
                            guard allowedRuleNames.contains(name) else { continue }
                        default:
                            break
                        }
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

        func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult] {
            []
        }

        func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad] {
            episodesByRuleName[rule.name] ?? []
        }
    }

    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        var tagsBySubjectID: [Int: [BangumiTag]] = [:]
        /// 设了就让 fetchSubject 原样返回它，用来测详情页字段补齐。
        var subjectOverride: BangumiItem?
        var fetchSubjectCallCount = 0
        /// 按标题找条目号时返回的搜索结果。
        var searchResults: [BangumiItem] = []
        private(set) var searchedKeywords: [String] = []

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }

        func search(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] {
            searchedKeywords.append(keyword)
            return searchResults
        }

        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            fetchSubjectCallCount += 1
            if let subjectOverride { return subjectOverride }
            let tags = tagsBySubjectID[subjectID] ?? []
            return BangumiItem(
                id: subjectID, name: "", nameCn: "", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: tags
            )
        }

        func fetchTags(subjectID: Int) async throws -> [BangumiTag] {
            tagsBySubjectID[subjectID] ?? []
        }

        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { [] }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { [] }
    }

    struct ProbingSourceSearchCoordinator: SourceSearchCoordinating {
        let probe: SearchLoadProbe
        let result: SearchResult

        func search(
            keyword: String,
            rules: [CezzuRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                Task {
                    continuation.yield(.ruleStarted(name: result.ruleName))
                    continuation.yield(.ruleResults(name: result.ruleName, results: [result]))
                    _ = await probe.waitForFetchStarted(timeout: .seconds(1))
                    await probe.recordSearchFinish()
                    continuation.yield(.finished)
                    continuation.finish()
                }
            }
        }

        func searchAll(
            keywords: [String],
            rules: [CezzuRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                Task {
                    continuation.yield(.ruleStarted(name: result.ruleName))
                    continuation.yield(.ruleResults(name: result.ruleName, results: [result]))
                    _ = await probe.waitForFetchStarted(timeout: .seconds(1))
                    await probe.recordSearchFinish()
                    continuation.yield(.finished)
                    continuation.finish()
                }
            }
        }
    }

    struct ProbingRuleEngine: RuleEngine {
        let probe: SearchLoadProbe
        let roads: [EpisodeRoad]

        func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult] {
            []
        }

        func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad] {
            await probe.markFetchStarted()
            return roads
        }
    }

    @Test("load picks one source per rule and prepares first-episode playback")
    func loadSelectsFirstSourceAndCreatesPlaybackRequest() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Sousou no Frieren",
            nameCn: "葬送的芙莉莲",
            summary: "",
            airDate: "2023-09-29",
            rank: 5,
            ratingScore: 9.1,
            images: .empty,
            tags: []
        )
        let ageRule = Self.makeRule(name: "AGE")
        let anfunsRule = Self.makeRule(name: "AnFuns")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "葬送的芙莉莲": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "葬送的芙莉莲",
                                detailURL: URL(string: "https://age.example/frieren")!,
                                ruleName: "AGE"
                            )
                        ]
                    ),
                    .ruleStarted(name: "AnFuns"),
                    .ruleResults(
                        name: "AnFuns",
                        results: [
                            SearchResult(
                                title: "葬送的芙莉莲 Season 1",
                                detailURL: URL(string: "https://anfuns.example/frieren")!,
                                ruleName: "AnFuns"
                            )
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/2")!, index: 1),
                        ]
                    )
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [ageRule, anfunsRule],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        #expect(model.sources.count == 2)
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.currentEpisodes.count == 2)

        let request = try #require(model.playbackRequestForFirstEpisode())
        #expect(request.rule.name == "AGE")
        #expect(request.roadIndex == 0)
        #expect(request.episodeIndex == 0)
        #expect(request.episode.title == "第 1 集")
    }

    @Test("load starts first source episode fetch before source search fully finishes")
    func loadStartsEpisodeFetchBeforeSearchFinishes() async throws {
        let item = BangumiItem(
            id: 2,
            name: "Yuru Camp",
            nameCn: "摇曳露营",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let probe = SearchLoadProbe()
        let coordinator = ProbingSourceSearchCoordinator(
            probe: probe,
            result: SearchResult(
                title: "摇曳露营",
                detailURL: URL(string: "https://age.example/yurucamp")!,
                ruleName: "AGE"
            )
        )
        let engine = ProbingRuleEngine(
            probe: probe,
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://play.example/yurucamp-1")!, index: 0)
                    ]
                )
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        #expect(await probe.fetchStartedBeforeSearchFinished)
        let request = try #require(model.playbackRequestForFirstEpisode())
        #expect(request.rule.name == "AGE")
        #expect(request.episode.title == "第 1 集")
    }

    @Test("load backfills tags from Bangumi subject details when item tags are empty")
    func loadBackfillsTagsWhenItemTagsAreEmpty() async throws {
        let item = BangumiItem(
            id: 3,
            name: "K-On!",
            nameCn: "轻音少女",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let api = FakeBangumiAPI()
        api.tagsBySubjectID[3] = [
            BangumiTag(name: "日常", count: 1200),
            BangumiTag(name: "校园", count: 980),
        ]
        let model = DetailViewModel(
            item: item,
            rules: [],
            api: api,
            searchCoordinator: FakeSourceSearchCoordinator(updates: [:]),
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.tags.count == 2)
        #expect(model.tags[0].name == "日常")
        #expect(model.tags[1].name == "校园")
    }

    @Test("updating rules after initial empty load retries source search")
    func updateRulesRetriesSourceSearch() async throws {
        let item = BangumiItem(
            id: 4,
            name: "Bocchi the Rock!",
            nameCn: "孤独摇滚！",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "孤独摇滚！": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "孤独摇滚！",
                                detailURL: URL(string: "https://age.example/bocchi")!,
                                ruleName: "AGE"
                            )
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/bocchi-1")!, index: 0)
                        ]
                    )
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()
        #expect(model.sources.isEmpty)
        #expect(model.sourceSearchFailed == "没有匹配到可播放源")

        await model.updateRules([rule])

        #expect(model.sources.count == 1)
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.currentEpisodes.count == 1)
    }

    @Test("history hint exposes resume request from regular detail entry")
    func historyHintBuildsResumeRequest() async throws {
        let item = BangumiItem(
            id: 5,
            name: "Girls Band Cry",
            nameCn: "少女乐队的呐喊",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(updates: [:])
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-1")!, index: 0)
                        ]
                    ),
                    EpisodeRoad(
                        index: 1,
                        label: "线路 2",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-alt-1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/gbc-alt-2")!, index: 1),
                        ]
                    ),
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            historyHint: HistoryResumeHint(
                bangumiTitle: item.displayName,
                coverURLString: nil,
                detailURL: URL(string: "https://age.example/gbc")!,
                ruleName: "AGE",
                episodeIndex: 1,
                episodeTitle: "第 2 集",
                positionMs: 601_000
            ),
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        let request = try #require(model.playbackRequestForResume())
        #expect(model.selectedRoadIndex == 1)
        #expect(request.roadIndex == 1)
        #expect(request.episodeIndex == 1)
        #expect(request.episode.title == "第 2 集")
    }

    @Test("history hint does not expose resume request for a different road")
    func historyHintRejectsDifferentRoad() async throws {
        let item = BangumiItem(
            id: 6,
            name: "Girls Band Cry",
            nameCn: "少女乐队的呐喊",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(updates: [:])
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-1")!, index: 0),
                            Episode(title: "第 2 集（线路 1）", url: URL(string: "https://play.example/gbc-2")!, index: 1),
                        ]
                    ),
                    EpisodeRoad(
                        index: 1,
                        label: "线路 2",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-alt-1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/gbc-alt-2")!, index: 1),
                        ]
                    ),
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            historyHint: HistoryResumeHint(
                bangumiTitle: item.displayName,
                coverURLString: nil,
                detailURL: URL(string: "https://age.example/gbc")!,
                ruleName: "AGE",
                episodeIndex: 1,
                episodeTitle: "第 2 集",
                positionMs: 601_000
            ),
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()
        model.selectRoad(0)

        #expect(model.playbackRequestForResume() == nil)
    }

    /// 回归：条目是第三季、站点只有第一季时，旧逻辑会静默选中第一季 ——
    /// 详情页写着第三季，播出来是第一季，没有任何提示。
    /// 现在它照样进列表（丢掉会让列表凭空变短），但标签必须写明它是第几季。
    @Test("a source that only carries an earlier season is labelled with its real season")
    func loadLabelsWrongSeasonSource() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Kusuriya no Hitorigoto 2nd Season",
            nameCn: "药屋少女的呢喃 第三季",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "药屋少女的呢喃 第三季": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "药屋少女的呢喃",
                                detailURL: URL(string: "https://age.example/s1")!,
                                ruleName: "AGE"
                            )
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            api: FakeBangumiAPI(),
            searchCoordinator: coordinator,
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        let source = try #require(model.sources.first)
        #expect(source.seasonMatches == false)
        #expect(source.label == "AGE（第 1 季）")
    }

    /// 季度对得上的源必须排在对不上的前面，并且是被自动选中的那一个。
    @Test("a season-matching source outranks and is preferred over a mismatched one")
    func loadPrefersSeasonMatchingSource() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Kusuriya no Hitorigoto 3rd Season",
            nameCn: "药屋少女的呢喃 第三季",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "药屋少女的呢喃 第三季": [
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "药屋少女的呢喃",
                                detailURL: URL(string: "https://age.example/s1")!,
                                ruleName: "AGE"
                            ),
                            SearchResult(
                                title: "药屋少女的呢喃 第三季",
                                detailURL: URL(string: "https://age.example/s3")!,
                                ruleName: "AGE"
                            ),
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            api: FakeBangumiAPI(),
            searchCoordinator: coordinator,
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.sources.count == 2)
        let first = try #require(model.sources.first)
        #expect(first.result.detailURL.absoluteString == "https://age.example/s3")
        #expect(first.seasonMatches)
        #expect(model.selectedSource?.id == first.id)
    }

    /// 同一条规则可以贡献多个条目，全部保留；但强匹配必须排在弱匹配前面。
    @Test("every match from one rule is kept, best-scoring first")
    func loadKeepsEveryMatchRankedByScore() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Kusuriya no Hitorigoto",
            nameCn: "药屋少女的呢喃",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let weak = SearchResult(
            title: "药屋少女的呢喃 无删减版",
            detailURL: URL(string: "https://age.example/loose")!,
            ruleName: "AGE"
        )
        let exact = SearchResult(
            title: "Kusuriya no Hitorigoto",
            detailURL: URL(string: "https://age.example/exact")!,
            ruleName: "AGE"
        )
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "药屋少女的呢喃": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(name: "AGE", results: [weak]),
                ],
                "Kusuriya no Hitorigoto": [
                    .ruleResults(name: "AGE", results: [exact]),
                    .finished,
                ],
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            api: FakeBangumiAPI(),
            searchCoordinator: coordinator,
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.sources.count == 2)
        let first = try #require(model.sources.first)
        #expect(first.result.detailURL == exact.detailURL)
        // 同一条规则出多个条目时，胶囊标签要带上站点标题才区分得开
        #expect(model.sources.allSatisfy { $0.label.hasPrefix("AGE · ") })
    }

    /// 站点用别名收录（「药师少女的独语」），条目正名搜不到；infobox 别名必须被喂给站点搜索。
    @Test("sources reachable only through a Bangumi alias are still found")
    func loadFindsSourceViaAlias() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Kusuriya no Hitorigoto",
            nameCn: "药屋少女的呢喃",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: [],
            infobox: [BangumiInfoboxEntry(key: "别名", value: "药师少女的独语、The Apothecary Diaries")]
        )
        let rule = Self.makeRule(name: "AGE")
        let aliasHit = SearchResult(
            title: "药师少女的独语",
            detailURL: URL(string: "https://age.example/alias")!,
            ruleName: "AGE"
        )
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                // 正名和罗马音都搜不到东西，只有别名命中
                "药屋少女的呢喃": [.ruleStarted(name: "AGE"), .ruleResults(name: "AGE", results: [])],
                "药师少女的独语": [.ruleResults(name: "AGE", results: [aliasHit]), .finished],
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            api: FakeBangumiAPI(),
            searchCoordinator: coordinator,
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        let source = try #require(model.sources.first)
        #expect(source.result.detailURL == aliasHit.detailURL)
    }

    /// 站点上同一部番常有多条收录（不同版本 / 不同入口）。旧模型 `PlayableSource.id == ruleName`
    /// 让一条规则只能留一个，剩下的全被丢掉 —— 这是"能搜出多少影片"最大的一道闸门。
    @Test("one rule can contribute several sources")
    func loadKeepsMultipleEntriesFromOneRule() async {
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
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "孤独摇滚": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "孤独摇滚",
                                detailURL: URL(string: "https://age.example/a")!,
                                ruleName: "AGE"
                            ),
                            SearchResult(
                                title: "孤独摇滚 无修版",
                                detailURL: URL(string: "https://age.example/b")!,
                                ruleName: "AGE"
                            ),
                            // 完全不相干的，仍然要被挡掉
                            SearchResult(
                                title: "快把我哥带走",
                                detailURL: URL(string: "https://age.example/c")!,
                                ruleName: "AGE"
                            ),
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            api: FakeBangumiAPI(),
            searchCoordinator: coordinator,
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.sources.count == 2)
        #expect(
            Set(model.sources.map(\.result.detailURL.absoluteString))
                == ["https://age.example/a", "https://age.example/b"]
        )
        // 精确命中排在前面
        #expect(model.sources.first?.result.title == "孤独摇滚")
    }

    private static func makeRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "1",
            type: "anime",
            name: name,
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//div",
            searchName: "//a/text()",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
    }
    // MARK: - 从历史进详情页

    /// 回归：从「最近播放」进详情页时，条目是历史合成的 —— 封面是上次的播放截图，
    /// 简介 / 评分 / 标签全空。历史里存了条目号，就该用它把真条目换回来。
    @Test("历史带着条目号进来时，合成条目被换成 bangumi 上的真条目")
    func historyEntryWithSubjectIDRestoresRealSubject() async throws {
        let api = FakeBangumiAPI()
        api.subjectOverride = BangumiItem(
            id: 547888,
            name: "Re:ゼロから始める異世界生活",
            nameCn: "Re：从零开始的异世界生活",
            summary: "真简介",
            airDate: "2026-04-08",
            rank: 0,
            ratingScore: 8.2,
            images: BangumiImages(
                large: "https://lain.bgm.tv/l.jpg",
                common: "https://lain.bgm.tv/c.jpg",
                medium: "https://lain.bgm.tv/m.jpg",
                small: "https://lain.bgm.tv/s.jpg",
                grid: "https://lain.bgm.tv/g.jpg"
            ),
            tags: []
        )
        let hint = HistoryResumeHint(
            bangumiTitle: "Re：从零开始的异世界生活",
            coverURLString: "file:///tmp/frame.jpg",
            detailURL: URL(string: "https://age.example/rezero")!,
            ruleName: "AGE",
            episodeIndex: 0,
            episodeTitle: "第 1 集",
            positionMs: 1000,
            subjectID: 547888
        )
        let model = DetailViewModel(
            item: hint.item,
            rules: [],
            api: api,
            historyHint: hint,
            searchCoordinator: FakeSourceSearchCoordinator(updates: [:]),
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )
        // 进来时只有一张播放截图。
        #expect(model.item.images.large == "file:///tmp/frame.jpg")

        await model.load()

        #expect(model.item.id == 547888)
        #expect(model.item.images.large == "https://lain.bgm.tv/l.jpg")
        #expect(model.item.ratingScore == 8.2)
        #expect(model.summary == "真简介")
        // 条目号已经有了，不该再去搜一次。
        #expect(api.searchedKeywords.isEmpty)
    }

    /// 这次改动之前存下的历史没有条目号，只能按标题找回来。
    @Test("老历史没有条目号时按标题找回条目")
    func historyEntryWithoutSubjectIDResolvesByTitle() async throws {
        let api = FakeBangumiAPI()
        api.searchResults = [
            BangumiItem(
                id: 999, name: "别的番", nameCn: "别的番", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            ),
            BangumiItem(
                id: 547888, name: "Re:ゼロ", nameCn: "孤独摇滚", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            ),
        ]
        api.subjectOverride = BangumiItem(
            id: 547888, name: "Re:ゼロ", nameCn: "孤独摇滚", summary: "真简介", airDate: "",
            rank: 0, ratingScore: 0,
            images: BangumiImages(
                large: "https://lain.bgm.tv/l.jpg",
                common: "https://lain.bgm.tv/c.jpg",
                medium: "https://lain.bgm.tv/m.jpg",
                small: "https://lain.bgm.tv/s.jpg",
                grid: "https://lain.bgm.tv/g.jpg"
            ),
            tags: []
        )
        let hint = HistoryResumeHint(
            bangumiTitle: "孤独摇滚",
            coverURLString: "file:///tmp/frame.jpg",
            detailURL: URL(string: "https://age.example/bocchi")!,
            ruleName: "AGE",
            episodeIndex: 0,
            episodeTitle: "第 1 集",
            positionMs: 1000
        )
        let model = DetailViewModel(
            item: hint.item,
            rules: [],
            api: api,
            historyHint: hint,
            searchCoordinator: FakeSourceSearchCoordinator(updates: [:]),
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(api.searchedKeywords == ["孤独摇滚"])
        // 标题对得上的才算数，第一条同名不上的不能拿来顶。
        #expect(model.item.id == 547888)
        #expect(model.summary == "真简介")
    }

    @Test("标题在 bangumi 上找不到时维持原样，不能挂上别的番")
    func historyEntryKeepsSynthesizedItemWhenTitleIsUnknown() async throws {
        let api = FakeBangumiAPI()
        api.searchResults = [
            BangumiItem(
                id: 999, name: "毫不相干的番", nameCn: "毫不相干的番", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: []
            )
        ]
        let hint = HistoryResumeHint(
            bangumiTitle: "只有本地有的番",
            coverURLString: "file:///tmp/frame.jpg",
            detailURL: URL(string: "https://age.example/x")!,
            ruleName: "AGE",
            episodeIndex: 0,
            episodeTitle: "第 1 集",
            positionMs: 0
        )
        let model = DetailViewModel(
            item: hint.item,
            rules: [],
            api: api,
            historyHint: hint,
            searchCoordinator: FakeSourceSearchCoordinator(updates: [:]),
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.item.id == 0)
        #expect(api.fetchSubjectCallCount == 0)
        #expect(model.item.displayName == "只有本地有的番")
    }

}

@Suite("DetailViewModel metadata")
@MainActor
struct DetailViewModelMetadataTests {

    private func bareItem(id: Int = 1, heat: Int = 0) -> BangumiItem {
        BangumiItem(
            id: id, name: "ヤニねこ", nameCn: "尼古喵喵", summary: "", airDate: "",
            rank: 0, ratingScore: 7.1, images: .empty, tags: [], heat: heat
        )
    }

    private func makeModel(
        item: BangumiItem,
        api: DetailViewModelTests.FakeBangumiAPI
    ) -> DetailViewModel {
        DetailViewModel(item: item, rules: [], api: api)
    }

    /// trending 条目没有简介 / 标签 / infobox，进详情页必须靠 fetchSubject 补齐。
    @Test("loading a trending item backfills summary, tags, infobox and collection")
    func backfillsFromSubject() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        api.subjectOverride = BangumiItem(
            id: 1, name: "ヤニねこ", nameCn: "尼古喵喵", summary: "完整简介",
            airDate: "2026-07-02", rank: 1991, ratingScore: 7.1, images: .empty,
            tags: [BangumiTag(name: "搞笑", count: 741)],
            ratingTotal: 2242, eps: 0, platform: "TV",
            metaTags: ["TV", "日本", "漫画改"],
            totalEpisodes: 12,
            collection: BangumiCollection(wish: 1498, collect: 281, doing: 10111, onHold: 89, dropped: 173),
            infobox: [
                BangumiInfoboxEntry(key: "放送星期", value: "星期四"),
                BangumiInfoboxEntry(key: "导演", value: "木村拓"),
            ]
        )
        let model = makeModel(item: bareItem(), api: api)
        await model.load()

        #expect(model.summary == "完整简介")
        #expect(model.tags.first?.name == "搞笑")
        #expect(model.metaTags == ["TV", "日本", "漫画改"])
        #expect(model.airDate == "2026-07-02")
        // eps 是 0，话数必须来自 total_episodes
        #expect(model.episodeCount == 12)
        #expect(model.collection?.doing == 10111)
        #expect(model.ratingTotal == 2242)
    }

    /// 重复 load 不该反复打 subject 接口。
    @Test("subject is fetched only once across repeated loads")
    func fetchesSubjectOnce() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        await model.load()
        await model.load()
        #expect(api.fetchSubjectCallCount == 1)
    }

    /// 接口失败时详情页要保留传进来的数据，不能被清空。
    @Test("subject fetch failure keeps the seed item's own metadata")
    func failureKeepsSeedData() async {
        let api = FailingSubjectAPI()
        let seed = BangumiItem(
            id: 1, name: "N", nameCn: "名", summary: "种子简介", airDate: "2024-01-01",
            rank: 0, ratingScore: 8.0, images: .empty,
            tags: [BangumiTag(name: "奇幻", count: 5)], metaTags: ["TV"], totalEpisodes: 24
        )
        let model = DetailViewModel(item: seed, rules: [], api: api)
        await model.load()
        #expect(model.summary == "种子简介")
        #expect(model.tags.first?.name == "奇幻")
        #expect(model.metaTags == ["TV"])
        #expect(model.episodeCount == 24)
    }

    /// bgm 对匿名不可见的条目一律回 404。主体内容来自搜索结果照常渲染，
    /// 但几个 tab 不该甩一句「HTTP 404」给用户。
    @Test("restricted subjects explain the 404 instead of surfacing a status code")
    func restrictedSubjectTabMessage() async {
        let api = RestrictedSubjectAPI()
        let seed = BangumiItem(
            id: 36954, name: "N", nameCn: "受限条目", summary: "种子简介", airDate: "2007-02-23",
            rank: 0, ratingScore: 6.4, images: .empty, tags: []
        )
        let model = DetailViewModel(item: seed, rules: [], api: api)
        await model.load()
        await model.selectTab(.characters)

        #expect(model.summary == "种子简介")
        #expect(model.tabErrors[.characters]?.contains("不公开") == true)
        #expect(model.tabErrors[.characters]?.contains("404") == false)
    }

    /// 所有 subject 相关端点都回 404，模拟匿名不可见的条目。
    private final class RestrictedSubjectAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        private var notFound: BangumiAPIError { .http(status: 404) }
        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(
            keyword: String, sort: BangumiSearchSort, filter: BangumiSearchFilter,
            limit: Int, offset: Int
        ) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem { throw notFound }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { throw notFound }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { throw notFound }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { throw notFound }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { throw notFound }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { throw notFound }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { throw notFound }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { throw notFound }
    }

    /// 热度优先用 trending 榜单值，没有则回落到收藏总人数。
    @Test("heat prefers trending count and falls back to collection total")
    func heatFallback() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let trendingModel = makeModel(item: bareItem(heat: 9986), api: api)
        #expect(trendingModel.heat == 9986)
        #expect(trendingModel.heatIsTrending)

        api.subjectOverride = BangumiItem(
            id: 2, name: "N", nameCn: "名", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [],
            collection: BangumiCollection(wish: 10, collect: 20, doing: 30)
        )
        let collectionModel = makeModel(item: bareItem(id: 2), api: api)
        await collectionModel.load()
        #expect(collectionModel.heat == 60)
        #expect(!collectionModel.heatIsTrending)
    }

    /// 没有任何来源时热度为 0，UI 靠它决定不显示。
    @Test("heat is zero when neither trending count nor collection exists")
    func heatAbsent() {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        #expect(model.heat == 0)
        #expect(!model.heatIsTrending)
    }

    @Test("factRows renders known infobox keys in order and skips missing ones")
    func factRowsOrdering() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        api.subjectOverride = BangumiItem(
            id: 1, name: "N", nameCn: "名", summary: "", airDate: "2026-07-02",
            rank: 0, ratingScore: 0, images: .empty, tags: [],
            platform: "TV", episodeDuration: "24分",
            totalEpisodes: 12,
            infobox: [
                BangumiInfoboxEntry(key: "放送星期", value: "星期四"),
                BangumiInfoboxEntry(key: "导演", value: "木村拓"),
                BangumiInfoboxEntry(key: "无关键", value: "忽略我"),
            ]
        )
        let model = makeModel(item: bareItem(), api: api)
        await model.load()

        let labels = model.factRows.map(\.0)
        #expect(labels.prefix(5) == ["放送开始", "放送星期", "话数", "片长", "类型"])
        #expect(labels.contains("导演"))
        // infobox 里没被列入白名单的 key 不该冒出来
        #expect(!labels.contains("无关键"))
        #expect(model.factRows.first(where: { $0.0 == "话数" })?.1 == "12 话")
    }

    @Test("factRows is empty when nothing is known about the subject")
    func factRowsEmpty() {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        #expect(model.factRows.isEmpty)
    }

    private final class FailingSubjectAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        struct Boom: Error {}
        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(
            keyword: String, sort: BangumiSearchSort, filter: BangumiSearchFilter,
            limit: Int, offset: Int
        ) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem { throw Boom() }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
        func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] { [] }
        func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] { [] }
    }
}

@Suite("DetailFormat")
struct DetailFormatTests {

    @Test("heat abbreviates thousands and ten-thousands")
    func heatFormatting() {
        #expect(DetailFormat.heat(0) == "0")
        #expect(DetailFormat.heat(999) == "999")
        #expect(DetailFormat.heat(1000) == "1.0k")
        #expect(DetailFormat.heat(9986) == "10.0k")
        #expect(DetailFormat.heat(10000) == "1.0万")
        #expect(DetailFormat.heat(12152) == "1.2万")
    }

    @Test("grouped inserts thousand separators")
    func groupedFormatting() {
        #expect(DetailFormat.grouped(0) == "0")
        #expect(DetailFormat.grouped(999) == "999")
        #expect(DetailFormat.grouped(1000) == "1,000")
        #expect(DetailFormat.grouped(10111) == "10,111")
        #expect(DetailFormat.grouped(1234567) == "1,234,567")
        #expect(DetailFormat.grouped(-4200) == "-4,200")
    }
}
