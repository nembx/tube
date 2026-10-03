import Foundation
import Testing
@testable import CezzuKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 串行化 —— 测试共享 `StubURLProtocol.handler` 静态字段，并发跑会撞车。
@Suite("BangumiAPIClient", .serialized)
struct BangumiAPIClientTests {

    // MARK: - 旧接口补充通道
    //
    // 这些用例打网络桩，必须留在本 suite 里：`.serialized` 只在 suite 内部生效，
    // 另起一个 suite 会和这里并发跑，抢同一个 `StubURLProtocol.handler` 静态字段。

    /// 回归场景：一个只有旧接口能召回的条目，v0 返回空也必须出现在结果里。
    @Test("search surfaces subjects that v0 hides from anonymous clients")
    func searchIncludesLegacyOnlySubject() async throws {
        let session = URLSession.stub { req in
            if req.httpMethod == "POST" { return (200, Data(#"{"data":[]}"#.utf8)) }
            return (200, Data(BangumiLegacyFixtures.restrictedSubject.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(
            keyword: "受限条目", sort: .match, filter: .default, limit: 20, offset: 0
        )
        #expect(items.contains { $0.id == 36954 })
        #expect(items.first?.nameCn == "受限条目")
    }

    /// 旧接口只在第一页参与召回，翻页仍然是纯 v0 的语义。
    @Test("legacy channel is skipped when paging past the first page")
    func legacyChannelSkippedOnLaterPages() async throws {
        let legacyHit = Locked(false)
        let session = URLSession.stub { req in
            if req.httpMethod == "POST" { return (200, Data(#"{"data":[]}"#.utf8)) }
            legacyHit.value = true
            return (200, Data(BangumiLegacyFixtures.restrictedSubject.utf8))
        }
        let client = BangumiAPIClient(session: session)
        _ = try await client.search(
            keyword: "受限条目", sort: .match, filter: .default, limit: 20, offset: 20
        )
        #expect(legacyHit.value == false)
    }

    /// 带 tag / 评分 / 年份时旧接口无法参与筛选，不能启用。
    @Test("legacy channel is skipped when the filter narrows server-side")
    func legacyChannelSkippedWhenFilterNarrows() async throws {
        let legacyHit = Locked(false)
        let session = URLSession.stub { req in
            if req.httpMethod == "POST" { return (200, Data(#"{"data":[]}"#.utf8)) }
            legacyHit.value = true
            return (200, Data(BangumiLegacyFixtures.restrictedSubject.utf8))
        }
        let client = BangumiAPIClient(session: session)
        _ = try await client.search(
            keyword: "受限条目",
            sort: .match,
            filter: BangumiSearchFilter(tags: ["百合"]),
            limit: 20,
            offset: 0
        )
        #expect(legacyHit.value == false)
    }

    /// 旧通道报错（HTTP 200 + 错误对象）必须被吞掉，不能污染 v0 的结果。
    @Test("legacy channel error body never surfaces to the caller")
    func legacyErrorBodyIsSwallowed() async throws {
        let session = URLSession.stub { req in
            if req.httpMethod == "POST" { return (200, Data(Self.singleV0Item.utf8)) }
            return (200, Data(#"{"request":"/search/subject/x","code":404,"error":"Not Found"}"#.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(
            keyword: "甲乙", sort: .match, filter: .default, limit: 20, offset: 0
        )
        #expect(items.map(\.id) == [1])
    }

    /// 旧通道补进来的条目不能污染翻页游标，否则下一页会跳过 v0 结果。
    @Test("nextOffset tracks v0 only, ignoring promoted legacy items")
    func nextOffsetTracksV0Only() async throws {
        let session = URLSession.stub { req in
            if req.httpMethod == "POST" { return (200, Data(Self.singleV0Item.utf8)) }
            return (200, Data(BangumiLegacyFixtures.restrictedSubject.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let page = try await client.searchPage(
            keyword: "受限条目", sort: .match, filter: .default, limit: 20, offset: 0
        )
        #expect(page.items.count == 2)
        #expect(page.nextOffset == 1)
        #expect(page.hasMore == false)
    }

    static let singleV0Item = #"{"data":[{"id":1,"name":"甲","images":{"large":"L","common":"C","medium":"M","small":"S","grid":"G"},"rating":{"rank":0,"score":0}}]}"#

    /// 旧接口补充通道的空响应 —— 只关心 v0 的测试用它把 GET 打发掉。
    static let emptyLegacyBody = Data(#"{"results":0,"list":[]}"#.utf8)

    /// `trending` 应该向 next.bgm.tv 发 GET，带正确 query，并且解析 `{data:[{subject:...}]}`
    @Test("trending sends GET to next.bgm.tv and decodes wrapped subjects")
    func trendingHappyPath() async throws {
        let trendingJSON = """
        {
            "data": [
                {
                    "subject": {
                        "id": 467461,
                        "name": "Frieren",
                        "name_cn": "葬送的芙莉莲",
                        "summary": "",
                        "date": "2023-09-29",
                        "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
                        "rating": {"rank": 5, "score": 9.1},
                        "tags": []
                    }
                },
                {
                    "subject": {
                        "id": 100,
                        "name": "B",
                        "name_cn": "乙",
                        "images": {"large": "x", "common": "x", "medium": "x", "small": "x", "grid": "x"},
                        "rating": {"rank": 0, "score": 0}
                    }
                }
            ]
        }
        """
        let session = URLSession.stub(
            handler: { req in
                #expect(req.httpMethod == "GET")
                #expect(req.url?.host == "next.bgm.tv")
                #expect(req.url?.path == "/p1/trending/subjects")
                #expect(req.url?.query?.contains("type=2") == true)
                #expect(req.url?.query?.contains("limit=24") == true)
                #expect(req.url?.query?.contains("offset=0") == true)
                #expect(req.value(forHTTPHeaderField: "User-Agent")?.contains("nembx/Tube") == true)
                return (200, Data(trendingJSON.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.trending(limit: 24, offset: 0)
        #expect(items.count == 2)
        #expect(items[0].id == 467461)
        #expect(items[0].nameCn == "葬送的芙莉莲")
        #expect(items[0].ratingScore == 9.1)
        #expect(items[1].id == 100)
    }

    /// 热度在 subject 外层的 `count` 里，必须被回填进 item.heat；缺失时回落到 0。
    @Test("trending backfills outer count into item heat")
    func trendingBackfillsHeat() async throws {
        let trendingJSON = """
        {
            "data": [
                {
                    "subject": {
                        "id": 1,
                        "name": "A",
                        "nameCN": "甲",
                        "info": "12话 / 2026年7月2日 / 某导演",
                        "metaTags": ["TV", "日本"],
                        "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
                        "rating": {"rank": 1, "score": 8.0}
                    },
                    "count": 9986
                },
                {
                    "subject": {
                        "id": 2,
                        "name": "B",
                        "nameCN": "乙",
                        "images": {"large": "x", "common": "x", "medium": "x", "small": "x", "grid": "x"},
                        "rating": {"rank": 0, "score": 0}
                    }
                }
            ]
        }
        """
        let session = URLSession.stub(handler: { _ in (200, Data(trendingJSON.utf8)) })
        let client = BangumiAPIClient(session: session)
        let items = try await client.trending(limit: 2, offset: 0)
        #expect(items.count == 2)
        #expect(items[0].heat == 9986)
        #expect(items[0].info == "12话 / 2026年7月2日 / 某导演")
        #expect(items[0].metaTags == ["TV", "日本"])
        // 没有 count 的条目热度为 0，不能崩也不能串到上一条
        #expect(items[1].heat == 0)
        #expect(items[1].metaTags.isEmpty)
    }

    /// `search(keyword:sort:)` 应该向 api.bgm.tv 发 POST + JSON body，带关键字与排序。
    @Test("search sends POST with JSON body containing keyword and sort")
    func searchHappyPath() async throws {
        let searchJSON = """
        {
            "data": [
                {
                    "id": 1,
                    "name": "alpha",
                    "name_cn": "甲",
                    "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
                    "rating": {"rank": 1, "score": 8.0}
                }
            ]
        }
        """
        let session = URLSession.stub(
            handler: { req in
                // 搜索首页还会并发打一次旧接口的补充通道；断言只针对 v0 那条。
                guard req.httpMethod == "POST" else { return (200, Self.emptyLegacyBody) }
                #expect(req.url?.host == "api.bgm.tv")
                #expect(req.url?.path == "/v0/search/subjects")
                #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")

                // URLSession upload bodies via httpBody are not surfaced in URLProtocol's request,
                // so we read from httpBodyStream when present.
                let bodyData: Data = {
                    if let d = req.httpBody { return d }
                    if let s = req.httpBodyStream {
                        s.open()
                        defer { s.close() }
                        var data = Data()
                        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                        defer { buf.deallocate() }
                        while s.hasBytesAvailable {
                            let n = s.read(buf, maxLength: 4096)
                            if n <= 0 { break }
                            data.append(buf, count: n)
                        }
                        return data
                    }
                    return Data()
                }()
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let filter = json?["filter"] as? [String: Any]
                let tags = filter?["tag"] as? [String]
                #expect(json?["keyword"] as? String == "芙莉莲")
                #expect(json?["sort"] as? String == "score")
                #expect(tags?.isEmpty == true)
                #expect(filter?["nsfw"] as? Bool == false)

                return (200, Data(searchJSON.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(keyword: "芙莉莲", sort: .score, tag: "", limit: 30, offset: 0)
        #expect(items.count == 1)
        #expect(items[0].nameCn == "甲")
    }

    /// 高级筛选：多 tag、评分上下限、air_date 区间、includeNSFW=true 时不发 nsfw 字段。
    @Test("search forwards advanced filter as JSON body")
    func searchForwardsAdvancedFilter() async throws {
        let searchJSON = #"{ "data": [] }"#
        let session = URLSession.stub(handler: { req in
            guard req.httpMethod == "POST" else { return (200, Self.emptyLegacyBody) }
            let bodyData: Data = {
                if let d = req.httpBody { return d }
                if let s = req.httpBodyStream {
                    s.open()
                    defer { s.close() }
                    var data = Data()
                    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buf.deallocate() }
                    while s.hasBytesAvailable {
                        let n = s.read(buf, maxLength: 4096)
                        if n <= 0 { break }
                        data.append(buf, count: n)
                    }
                    return data
                }
                return Data()
            }()
            let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            let filter = json?["filter"] as? [String: Any]
            #expect((filter?["tag"] as? [String]) == ["校园", "原创"])
            #expect((filter?["rating"] as? [String]) == [">=8", "<=10"])
            #expect((filter?["air_date"] as? [String]) == [">=2020-01-01", "<2024-01-01"])
            // includeNSFW=true → nsfw 字段不应出现
            #expect(filter?["nsfw"] == nil)
            return (200, Data(searchJSON.utf8))
        })
        let client = BangumiAPIClient(session: session)
        var filter = BangumiSearchFilter(
            tags: ["校园", "原创"],
            ratingMin: 8,
            ratingMax: 10,
            includeNSFW: true
        )
        filter.setYearRange(min: 2020, max: 2023)

        _ = try await client.search(
            keyword: "k",
            sort: .heat,
            filter: filter,
            limit: 30,
            offset: 0
        )
    }

    /// includeNSFW=false 时 body 应显式带 nsfw:false。
    @Test("search keeps nsfw:false when filter excludes R18")
    func searchKeepsNSFWFalse() async throws {
        let searchJSON = #"{ "data": [] }"#
        let session = URLSession.stub(handler: { req in
            guard req.httpMethod == "POST" else { return (200, Self.emptyLegacyBody) }
            let bodyData: Data = {
                if let d = req.httpBody { return d }
                if let s = req.httpBodyStream {
                    s.open()
                    defer { s.close() }
                    var data = Data()
                    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buf.deallocate() }
                    while s.hasBytesAvailable {
                        let n = s.read(buf, maxLength: 4096)
                        if n <= 0 { break }
                        data.append(buf, count: n)
                    }
                    return data
                }
                return Data()
            }()
            let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            let filter = json?["filter"] as? [String: Any]
            #expect(filter?["nsfw"] as? Bool == false)
            #expect(filter?["rating"] == nil)
            #expect(filter?["air_date"] == nil)
            return (200, Data(searchJSON.utf8))
        })
        let client = BangumiAPIClient(session: session)
        _ = try await client.search(
            keyword: "k",
            sort: .match,
            filter: .default,
            limit: 30,
            offset: 0
        )
    }

    /// HTTP 5xx 应该抛 BangumiAPIError.http
    @Test("HTTP 500 throws .http error")
    func http500Throws() async {
        let session = URLSession.stub(handler: { _ in (500, Data()) })
        let client = BangumiAPIClient(session: session)
        await #expect(throws: BangumiAPIError.self) {
            _ = try await client.trending(limit: 1, offset: 0)
        }
    }

    /// 返回非法 JSON 应该抛 .decoding
    @Test("malformed JSON throws .decoding error")
    func malformedJSONThrows() async {
        let session = URLSession.stub(handler: { _ in (200, Data("not json".utf8)) })
        let client = BangumiAPIClient(session: session)
        do {
            _ = try await client.trending(limit: 1, offset: 0)
            Issue.record("expected to throw")
        } catch let error as BangumiAPIError {
            switch error {
            case .decoding: break
            default: Issue.record("expected .decoding, got \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// 空 tag 时 search 不带 tag 过滤（filter.tag 是空数组）
    @Test("search with empty tag sends empty tag list")
    func searchWithEmptyTag() async throws {
        let session = URLSession.stub(
            handler: { req in
                let bodyData: Data = {
                    if let d = req.httpBody { return d }
                    if let s = req.httpBodyStream {
                        s.open()
                        defer { s.close() }
                        var data = Data()
                        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                        defer { buf.deallocate() }
                        while s.hasBytesAvailable {
                            let n = s.read(buf, maxLength: 4096)
                            if n <= 0 { break }
                            data.append(buf, count: n)
                        }
                        return data
                    }
                    return Data()
                }()
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let filter = json?["filter"] as? [String: Any]
                let tags = filter?["tag"] as? [String]
                #expect(tags?.isEmpty == true)
                return (200, Data(#"{"data":[]}"#.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(tag: "", limit: 10, offset: 0)
        #expect(items.isEmpty)
    }

    /// 回归：`rank: [">0", ...]` 会把 Bangumi 上 rank=0 的条目（新番续作、未放送、
    /// 剧场版）整批排除。实测「药屋少女」带 rank 过滤只剩 8 条、去掉后 17 条，
    /// 被砍掉的正是第三季与剧场版。body 里不允许再出现 rank 字段。
    @Test("search never sends a rank filter")
    func searchOmitsRankFilter() async throws {
        let session = URLSession.stub(handler: { req in
            guard req.httpMethod == "POST" else { return (200, Self.emptyLegacyBody) }
            let json = try? JSONSerialization.jsonObject(with: req.stubBody) as? [String: Any]
            let filter = json?["filter"] as? [String: Any]
            #expect(filter?["rank"] == nil)
            #expect((filter?["type"] as? [Int]) == [2])
            return (200, Data(#"{"data":[]}"#.utf8))
        })
        let client = BangumiAPIClient(session: session)
        _ = try await client.search(
            keyword: "药屋少女",
            sort: .match,
            filter: .default,
            limit: 30,
            offset: 0
        )
    }

    /// bgm.tv 会偶发直接断连。断一次不该让搜索页清空结果——重试一次要能自愈。
    ///
    /// 用 `trending` 而不是 `search` 来数请求次数：搜索首页会并发打一次旧接口的
    /// 补充通道，两条流共用同一个 stub 计数器，数出来的不是重试次数。
    @Test("transient transport failure is retried once and succeeds")
    func transientFailureIsRetried() async throws {
        let session = URLSession.stubFailing(
            failures: 1,
            then: (200, Data(#"{"data":[]}"#.utf8))
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.trending(limit: 10, offset: 0)
        #expect(items.isEmpty)
        #expect(FailingStubURLProtocol.attempts == 2)
    }

    /// 连续两次都断，才向调用方抛错——重试是一次，不是无限。
    @Test("transport failure surfaces after the single retry is exhausted")
    func repeatedFailureThrows() async {
        let session = URLSession.stubFailing(
            failures: 2,
            then: (200, Data(#"{"data":[]}"#.utf8))
        )
        let client = BangumiAPIClient(session: session)
        await #expect(throws: BangumiAPIError.self) {
            _ = try await client.trending(limit: 1, offset: 0)
        }
        #expect(FailingStubURLProtocol.attempts == 2)
    }

    /// HTTP 5xx 不是瞬时网络错误，重试它只是白白多打一次服务器。
    @Test("HTTP 500 is not retried")
    func http500IsNotRetried() async {
        let session = URLSession.stubFailing(failures: 0, then: (500, Data()))
        let client = BangumiAPIClient(session: session)
        await #expect(throws: BangumiAPIError.self) {
            _ = try await client.trending(limit: 1, offset: 0)
        }
        #expect(FailingStubURLProtocol.attempts == 1)
    }

    @Test("fetchTags decodes subject tags from Bangumi subject details")
    func fetchTagsDecodesSubjectTags() async throws {
        let subjectJSON = """
        {
            "id": 1,
            "name": "alpha",
            "name_cn": "甲",
            "summary": "",
            "date": "",
            "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
            "rating": {"rank": 1, "score": 8.0},
            "tags": [
                {"name": "校园", "count": 321},
                {"name": "日常", "count": 280}
            ]
        }
        """
        let session = URLSession.stub(
            handler: { req in
                #expect(req.httpMethod == "GET")
                #expect(req.url?.host == "api.bgm.tv")
                #expect(req.url?.path == "/v0/subjects/1")
                return (200, Data(subjectJSON.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let tags = try await client.fetchTags(subjectID: 1)
        #expect(tags.count == 2)
        #expect(tags[0].name == "校园")
        #expect(tags[0].count == 321)
        #expect(tags[1].name == "日常")
    }

    @Test("fetchEpisodes asks for regular episodes and decodes the envelope")
    func fetchEpisodesDecodesRegularEpisodes() async throws {
        let json = """
        {"data": [
            {"id": 1303316, "ep": 1, "sort": 1, "name": "温泉と誓い", "name_cn": "温泉与誓言",
             "airdate": "2024-04-09", "duration": "00:23:40", "desc": "泉の運命が動き出す",
             "comment": 40},
            {"id": 1303317, "ep": 2, "sort": 2, "name": "踏み出す勇気", "name_cn": "",
             "airdate": "2024-04-16", "comment": 12}
        ]}
        """
        let session = URLSession.stub { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.host == "api.bgm.tv")
            #expect(req.url?.path == "/v0/episodes")
            let query = req.url?.query ?? ""
            #expect(query.contains("subject_id=425978"))
            // type=0 才是正片，不带的话 SP / OP / 预告会混进集数列表。
            #expect(query.contains("type=0"))
            return (200, Data(json.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let episodes = try await client.fetchEpisodes(subjectID: 425978)

        #expect(episodes.count == 2)
        #expect(episodes[0].id == 1303316)
        #expect(episodes[0].commentCount == 40)
        #expect(episodes[0].displayTitle == "温泉与誓言")
        #expect(episodes[0].displayHeadline == "ep.1 温泉与誓言")
        #expect(episodes[0].duration == "00:23:40")
        #expect(episodes[0].desc == "泉の運命が動き出す")
        // duration / desc 缺字段时留空，不能崩。
        #expect(episodes[1].duration.isEmpty)
        // 没有中文名时退回原文名，不能显示成空标题。
        #expect(episodes[1].displayTitle == "踏み出す勇気")
    }

    @Test("fetchEpisodeComments parses top-level floors from the episode page")
    func fetchEpisodeCommentsParsesFloors() async throws {
        let session = URLSession.stub { req in
            #expect(req.url?.host == "bgm.tv")
            #expect(req.url?.path == "/ep/1303316")
            return (200, Data(BangumiEpisodePageFixtures.commentList.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let comments = try await client.fetchEpisodeComments(episodeID: 1303316)

        // 楼中楼不算独立一条，两个主楼就是两条。
        #expect(comments.count == 2)
        #expect(comments[0].authorName == "Saito")
        #expect(comments[0].floor == "#1")
        #expect(comments[0].publishedAt == "2024-4-9 01:29")
        #expect(comments[0].body.contains("温泉と誓い"))
        // <br> 是唯一的换行来源，几段话不能黏成一行。
        #expect(comments[0].body.contains("\n"))
        #expect(comments[0].avatarURL?.absoluteString == "https://lain.bgm.tv/pic/user/l/000/73/86/738634.jpg?r=1693060285&hd=1")
        #expect(comments[1].authorName == "shiraki")

        // 楼中楼挂在主楼下面，自己不再单独占一层。
        #expect(comments[1].replies.map(\.authorName) == ["楼中楼"])
        #expect(comments[1].replies[0].floor == "#2-1")
        #expect(comments[1].replies[0].body == "这是回复")
    }

    @Test("楼里贴的图收进来，表情不算图")
    func fetchEpisodeCommentsCollectsImages() async throws {
        let session = URLSession.stub { _ in
            (200, Data(BangumiEpisodePageFixtures.commentWithImage.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let comments = try await client.fetchEpisodeComments(episodeID: 1)

        let comment = try #require(comments.first)
        #expect(comment.imageURLs.map(\.absoluteString) == ["https://img.example/photo.webp"])
        #expect(comment.body == "说得好")
    }

    @Test("只有一张图没有文字的楼也要留下")
    func fetchEpisodeCommentsKeepsImageOnlyFloor() async throws {
        let session = URLSession.stub { _ in
            (200, Data(BangumiEpisodePageFixtures.imageOnlyComment.utf8))
        }
        let client = BangumiAPIClient(session: session)
        let comments = try await client.fetchEpisodeComments(episodeID: 1)

        #expect(comments.count == 1)
        #expect(comments[0].body.isEmpty)
        #expect(comments[0].imageURLs.count == 1)
    }

    @Test("an episode page without any comment renders as an empty list, not an error")
    func fetchEpisodeCommentsOnEmptyPage() async throws {
        let session = URLSession.stub { _ in
            (200, Data("<html><body><div id=\"comment_list\"></div></body></html>".utf8))
        }
        let client = BangumiAPIClient(session: session)
        #expect(try await client.fetchEpisodeComments(episodeID: 1).isEmpty)
    }
}

enum BangumiEpisodePageFixtures {
    /// 截自 bgm.tv/ep/1303316，保留了主楼 + 楼中楼的嵌套结构。
    static let commentList = """
    <html><body>
    <div id="comment_list" class="commentList comment-list borderNeue">
      <div id="post_1507799" class="light_odd row row_reply clearit" data-item-user="tcnshi">
        <div class="post_actions re_info">
          <div class="action"><small><a href="#post_1507799" class="floor-anchor">#1</a> - 2024-4-9 01:29</small></div>
        </div>
        <a href="/user/tcnshi" class="avatar"><span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/000/73/86/738634.jpg?r=1693060285&hd=1')"></span></a>
        <div class="inner">
          <strong><a href="/user/tcnshi" class="l">Saito</a></strong>
          <div class="reply_content"><div class="message clearit">EPISODE 1<br />温泉と誓い</div></div>
        </div>
      </div>
      <div id="post_1508381" class="light_even row row_reply clearit" data-item-user="shiraki">
        <div class="post_actions re_info">
          <div class="action"><small><a href="#post_1508381" class="floor-anchor">#2</a> - 2024-4-9 21:47</small></div>
        </div>
        <a href="/user/shiraki" class="avatar"><span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/000/31/80/318040.jpg')"></span></a>
        <div class="inner">
          <strong><a href="/user/shiraki" class="l">shiraki</a></strong>
          <div class="reply_content">
            <div class="message clearit">还剩下赛车和赛艇还没有对应的美少女动画</div>
            <div class="topic_sub_reply" id="topic_reply_1508381">
              <div id="post_1508400" class="sub_reply_bg clearit" data-item-user="other">
                <div class="post_actions re_info">
                  <div class="action"><small><a href="#post_1508400" class="floor-anchor">#2-1</a> - 2024-4-9 22:20</small></div>
                </div>
                <a href="/user/other" class="avatar"><span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/000/28/27/282714.jpg')"></span></a>
                <div class="inner"><strong><a href="/user/other" class="l">楼中楼</a></strong>
                  <div class="cmt_sub_content">这是回复</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    </body></html>
    """

    /// 一条带图的楼：真图是 `img.code`，后面那个是 bgm 表情，不该算进图里。
    static let commentWithImage = """
    <html><body>
    <div id="comment_list">
      <div id="post_1" class="row row_reply clearit" data-item-user="a">
        <div class="post_actions re_info">
          <div class="action"><small><a href="#post_1" class="floor-anchor">#1</a> - 2026-4-15 10:00</small></div>
        </div>
        <a href="/user/a" class="avatar"><span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/1.jpg')"></span></a>
        <div class="inner">
          <strong><a href="/user/a" class="l">someone</a></strong>
          <div class="reply_content"><div class="message clearit">说得好<img src="https://img.example/photo.webp" class="code" alt="" /><img src="//lain.bgm.tv/img/smiles/musume/musume_06.gif" class="smile smile-dynamic" alt="(musume_06)" /></div></div>
        </div>
      </div>
    </div>
    </body></html>
    """

    static let imageOnlyComment = """
    <html><body>
    <div id="comment_list">
      <div id="post_1" class="row row_reply clearit" data-item-user="a">
        <div class="post_actions re_info">
          <div class="action"><small><a href="#post_1" class="floor-anchor">#1</a> - 2026-4-15 10:00</small></div>
        </div>
        <a href="/user/a" class="avatar"><span class="avatarNeue" style="background-image:url('//lain.bgm.tv/pic/user/l/1.jpg')"></span></a>
        <div class="inner">
          <strong><a href="/user/a" class="l">someone</a></strong>
          <div class="reply_content"><div class="message clearit"><img src="https://img.example/only.png" class="code" alt="" /></div></div>
        </div>
      </div>
    </div>
    </body></html>
    """
}

// MARK: - Request body helper

extension URLRequest {
    /// URLSession 把 `httpBody` 搬进 `httpBodyStream` 后 URLProtocol 才看得到，两边都读一次。
    var stubBody: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

// MARK: - URLProtocol stub helper

/// 一个用 URLProtocol 拦截的 URLSession，给 BangumiAPIClient 单测用。
extension URLSession {
    static func stub(
        handler: @escaping @Sendable (URLRequest) -> (statusCode: Int, body: Data)
    ) -> URLSession {
        StubURLProtocol.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://stub")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 前 `failures` 次请求模拟断连，之后返回固定响应。用来测重试。
extension URLSession {
    static func stubFailing(
        failures: Int,
        then response: (statusCode: Int, body: Data)
    ) -> URLSession {
        FailingStubURLProtocol.attempts = 0
        FailingStubURLProtocol.remainingFailures = failures
        FailingStubURLProtocol.response = response
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FailingStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

final class FailingStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var attempts = 0
    nonisolated(unsafe) static var remainingFailures = 0
    nonisolated(unsafe) static var response: (statusCode: Int, body: Data) = (200, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.attempts += 1
        if Self.remainingFailures > 0 {
            Self.remainingFailures -= 1
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let (status, body) = Self.response
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "http://stub")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
