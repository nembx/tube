import Foundation
@preconcurrency import Kanna

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Bangumi.tv 数据接口的抽象。注入用 protocol，方便单测。
public protocol BangumiAPIClientProtocol: Sendable {
    /// 拿热门番剧（next.bgm.tv `/p1/trending/subjects`）
    func trending(limit: Int, offset: Int) async throws -> [BangumiItem]
    /// 按 tag 拿番剧列表（api.bgm.tv `/v0/search/subjects`）
    func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem]
    /// 按关键字搜索番剧，并支持排序与高级筛选。
    func search(
        keyword: String,
        sort: BangumiSearchSort,
        filter: BangumiSearchFilter,
        limit: Int,
        offset: Int
    ) async throws -> [BangumiItem]
    /// 兼容旧调用方的简易关键字搜索（单 tag、不含 R18）。
    /// 默认实现委派到 `search(keyword:sort:filter:...)`。
    func search(
        keyword: String,
        sort: BangumiSearchSort,
        tag: String,
        limit: Int,
        offset: Int
    ) async throws -> [BangumiItem]
    /// 同 `search(keyword:sort:filter:...)`，但额外带回翻页游标。
    /// 默认实现按「一页 = limit 条」推算，只有 `BangumiAPIClient` 会给出真实游标。
    func searchPage(
        keyword: String,
        sort: BangumiSearchSort,
        filter: BangumiSearchFilter,
        limit: Int,
        offset: Int
    ) async throws -> BangumiSearchPage
    func fetchSubject(subjectID: Int) async throws -> BangumiItem
    func fetchTags(subjectID: Int) async throws -> [BangumiTag]
    func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter]
    func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson]
    func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment]
    func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview]
    /// 条目下的正片分集（`/v0/episodes?type=0`）。
    func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode]
    /// 单集页里的吐槽（`bgm.tv/ep/{id}`）。
    func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment]
}

extension BangumiAPIClientProtocol {
    /// 默认实现：把单 tag 旧 API 转成新的 filter API。
    public func search(
        keyword: String,
        sort: BangumiSearchSort,
        tag: String,
        limit: Int,
        offset: Int
    ) async throws -> [BangumiItem] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = BangumiSearchFilter(
            tags: trimmed.isEmpty ? [] : [trimmed]
        )
        return try await search(
            keyword: keyword,
            sort: sort,
            filter: filter,
            limit: limit,
            offset: offset
        )
    }

    /// 默认实现：没有真实游标可用时，按「返回满一页就还有下一页」推算。
    public func searchPage(
        keyword: String,
        sort: BangumiSearchSort,
        filter: BangumiSearchFilter,
        limit: Int,
        offset: Int
    ) async throws -> BangumiSearchPage {
        let items = try await search(
            keyword: keyword,
            sort: sort,
            filter: filter,
            limit: limit,
            offset: offset
        )
        return BangumiSearchPage(
            items: items,
            nextOffset: offset + items.count,
            hasMore: items.count == limit
        )
    }
}

/// Bangumi.tv 真实 HTTP 客户端。
///
/// 用 `URLSession` 直接打 `https://api.bgm.tv` / `https://next.bgm.tv`。
/// 不复用 `HTTPClient`，因为：
///   - HTTPClient 的 API 是按 `TubeRule` 注 UA / Referer 设计的，跟 Bangumi 完全不同
///   - Bangumi 要求一个固定 UA（`nembx/Tube/Version (平台) (主页)`），而不是规则随机 UA
///   - Bangumi POST 走 JSON body 而不是 form-urlencoded
public actor BangumiAPIClient: BangumiAPIClientProtocol {
    /// 跟随「设置 → Bangumi 服务」当前选中的站点。
    public static let shared = BangumiAPIClient(site: BangumiSiteSettings.selectedSite())

    let session: URLSession
    let userAgent: String
    /// next.<host> 的 /p1 接口（热门、短评、长评、单集吐槽）。镜像站同样代理；
    /// 只有测试显式注入 nil 时，热门才回落到 API 搜索、评论才回落到网页抓取。
    private let nextDomain: URL?
    let apiDomain: URL
    private let webDomain: URL
    /// 实际使用的站点（图床改写也按它推导）。
    let site: BangumiSite

    public init(
        session: URLSession? = nil,
        userAgent: String = BangumiAPIClient.defaultUserAgent,
        site: BangumiSite = .official,
        apiDomain: URL? = nil,
        nextDomain: URL? = nil,
        webDomain: URL? = nil
    ) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: cfg)
        }
        self.userAgent = userAgent
        self.site = site
        self.apiDomain = apiDomain ?? site.apiDomain
        self.nextDomain = nextDomain ?? site.nextDomain
        // 网页 HTML 只在 /p1 接口失败时作回落；镜像站的网页层在 Anubis 之后抓不到，
        // 所以回落固定抓官方 bgm.tv。JSON API、/p1 与图床都跟随站点。
        self.webDomain = webDomain ?? site.webPageBase
    }

    /// bgm 要求的 UA 形态：`{开发者}/{应用}/{版本} ({平台}) ({主页})`，用库默认 UA 可能被封。
    public static let defaultUserAgent: String = {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
        #if os(macOS)
            let platform = "macOS"
        #else
            let platform = "iOS"
        #endif
        return "nembx/Tube/\(version) (\(platform)) (https://github.com/nembx/tube)"
    }()

    // MARK: - Trending (next.bgm.tv)

    public func trending(limit: Int = 24, offset: Int = 0) async throws -> [BangumiItem] {
        // 没有 next 域（只在测试显式注入 nil 时发生）：用 API 按收藏人数排序近似「热门」。
        guard let nextDomain else {
            return try await searchSubjects(
                keyword: "",
                sort: .heat,
                limit: limit,
                offset: offset,
                filter: BangumiSearchFilter()
            )
        }
        var components = URLComponents(
            url: nextDomain.appendingPathComponent("/p1/trending/subjects"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        let data = try await perform(req)
        return try decodeTrending(data)
    }

    // MARK: - Search by tag (api.bgm.tv)

    public func search(
        tag: String,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [BangumiItem] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = BangumiSearchFilter(tags: trimmed.isEmpty ? [] : [trimmed])
        return try await searchSubjects(
            keyword: "",
            sort: .rank,
            limit: limit,
            offset: offset,
            filter: filter
        )
    }

    public func search(
        keyword: String,
        sort: BangumiSearchSort,
        filter: BangumiSearchFilter,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [BangumiItem] {
        try await searchPage(
            keyword: keyword,
            sort: sort,
            filter: filter,
            limit: limit,
            offset: offset
        ).items
    }

    /// 双通道召回。
    ///
    /// `/v0/search/subjects` 是主体（有 tags / infobox，支持服务端筛选），
    /// 但它对匿名客户端会静默丢掉一部分条目。旧接口 `/search/subject` 不受
    /// 该策略约束，在第一页作为补充通道并进来。
    ///
    /// 只在第一页启用旧通道：精确片名在旧接口里都排在最前几条，一页足够；
    /// 同时彻底避开两条流各自分页时的游标对齐问题。
    public func searchPage(
        keyword: String,
        sort: BangumiSearchSort,
        filter: BangumiSearchFilter,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> BangumiSearchPage {
        async let legacy = legacyItemsIfEligible(
            keyword: keyword,
            filter: filter,
            offset: offset
        )
        let v0Items: [BangumiItem]
        do {
            v0Items = try await searchSubjects(
                keyword: keyword,
                sort: sort,
                limit: limit,
                offset: offset,
                filter: filter
            )
        } catch {
            _ = await legacy
            throw error
        }
        let merged = BangumiSearchPage.merge(
            v0Items: v0Items,
            legacyItems: await legacy,
            keyword: keyword
        )
        return BangumiSearchPage(
            items: merged,
            nextOffset: offset + v0Items.count,
            hasMore: v0Items.count == limit
        )
    }

    public func fetchSubject(subjectID: Int) async throws -> BangumiItem {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode(BangumiItem.self, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchTags(subjectID: Int) async throws -> [BangumiTag] {
        try await fetchSubject(subjectID: subjectID).tags
    }

    public func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)/characters")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode([BangumiRelatedCharacter].self, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)/persons")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode([BangumiRelatedPerson].self, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    // MARK: - 短评 / 长评 / 单集吐槽（next.<host> 的 /p1 JSON；网页抓取只作回落）
    //
    // 以前三者都抓 bgm.tv 网页：镜像站的网页层在 Anubis 之后，App 抓不到，
    // 于是选了镜像的用户看评论还得翻墙。/p1 接口镜像站是代理的（2026-10 实测
    // next.bangumi.lat 与 next.bgm.tv 逐字节一致），JSON 也比 XPath 稳得多。
    // 接口失败才回落到网页；取消要原样抛出，不能被回落吞掉。

    public func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] {
        if let nextDomain {
            do {
                let req = try makeP1Request(
                    nextDomain,
                    path: "/p1/subjects/\(subjectID)/comments",
                    query: [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: "0")]
                )
                let data = try await perform(req)
                return try Self.decodeP1(P1ListEnvelope<P1SubjectComment>.self, from: data)
                    .data.compactMap(Self.subjectComment)
            } catch BangumiAPIError.cancelled {
                throw BangumiAPIError.cancelled
            } catch {
                // 回落到网页抓取
            }
        }
        let html = try await fetchWebHTML(path: "/subject/\(subjectID)/comments")
        return try parseComments(html: html)
    }

    public func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] {
        if let nextDomain {
            do {
                let req = try makeP1Request(
                    nextDomain,
                    path: "/p1/subjects/\(subjectID)/reviews",
                    query: [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: "0")]
                )
                let data = try await perform(req)
                return try Self.decodeP1(P1ListEnvelope<P1Review>.self, from: data)
                    .data.compactMap(review)
            } catch BangumiAPIError.cancelled {
                throw BangumiAPIError.cancelled
            } catch {
                // 回落到网页抓取
            }
        }
        let html = try await fetchWebHTML(path: "/subject/\(subjectID)/reviews")
        return try parseReviews(html: html)
    }

    public func fetchEpisodes(subjectID: Int) async throws -> [BangumiEpisode] {
        var components = URLComponents(
            url: apiDomain.appendingPathComponent("/v0/episodes"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "subject_id", value: "\(subjectID)"),
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        guard let url = components?.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode(EpisodesEnvelope.self, from: data).data
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchEpisodeComments(episodeID: Int) async throws -> [BangumiEpisodeComment] {
        if let nextDomain {
            do {
                let req = try makeP1Request(nextDomain, path: "/p1/episodes/\(episodeID)/comments")
                let data = try await perform(req)
                return Self.episodeComments(try Self.decodeP1([P1EpisodeComment].self, from: data))
            } catch BangumiAPIError.cancelled {
                throw BangumiAPIError.cancelled
            } catch {
                // 回落到网页抓取
            }
        }
        let html = try await fetchWebHTML(path: "/ep/\(episodeID)")
        return try parseEpisodeComments(html: html)
    }

    private func makeP1Request(_ nextDomain: URL, path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(url: nextDomain.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw BangumiAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        return req
    }

    private static func decodeP1<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    /// 短评的收藏状态文案，和网页上 `small.grey` 里的字一致。
    private static let p1CollectionLabels: [Int: String] = [1: "想看", 2: "看过", 3: "在看", 4: "搁置", 5: "抛弃"]

    private static func subjectComment(_ raw: P1SubjectComment) -> BangumiSubjectComment? {
        let body = (raw.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let rate = raw.rate ?? 0
        return BangumiSubjectComment(
            id: String(raw.id),
            authorName: raw.user?.displayName ?? "",
            avatarURL: raw.user?.avatarURL,
            stateLabel: p1CollectionLabels[raw.type ?? 0] ?? "",
            // 视图把 "stars" 换成 ★，和网页 class 名保持同一形态。
            ratingLabel: rate > 0 ? "stars\(rate)" : "",
            publishedAt: p1DateString(raw.updatedAt),
            body: body
        )
    }

    private func review(_ raw: P1Review) -> BangumiSubjectReview? {
        let title = (raw.entry.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let replies = raw.entry.replies ?? 0
        return BangumiSubjectReview(
            id: String(raw.entry.id),
            title: title,
            authorName: raw.user?.displayName ?? "",
            avatarURL: raw.user?.avatarURL,
            publishedAt: Self.p1DateString(raw.entry.createdAt),
            replyCount: replies > 0 ? "\(replies) 回复" : "",
            summary: (raw.entry.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            // 全文在浏览器里打开：浏览器能过 Anubis，镜像用户就用镜像站的网页。
            url: site.webDomain.appendingPathComponent("/blog/\(raw.entry.id)")
        )
    }

    /// 楼层按返回顺序编号（`#1`、`#1-1`），和网页上的写法一致。
    /// 被删除的楼（state 6 用户删 / 7 管理删）网页上也不显示正文，直接丢掉。
    private static func episodeComments(_ raw: [P1EpisodeComment]) -> [BangumiEpisodeComment] {
        var result: [BangumiEpisodeComment] = []
        for item in raw where !isDeleted(item) {
            let floor = "#\(result.count + 1)"
            let (body, images) = p1Body(item.content ?? "")
            var replies: [BangumiEpisodeComment] = []
            for reply in item.replies ?? [] where !isDeleted(reply) {
                let (replyBody, replyImages) = p1Body(reply.content ?? "")
                guard !(replyBody.isEmpty && replyImages.isEmpty) else { continue }
                replies.append(BangumiEpisodeComment(
                    id: String(reply.id),
                    floor: "\(floor)-\(replies.count + 1)",
                    authorName: reply.user?.displayName ?? "",
                    avatarURL: reply.user?.avatarURL,
                    publishedAt: p1DateString(reply.createdAt),
                    body: replyBody,
                    imageURLs: replyImages
                ))
            }
            guard !(body.isEmpty && images.isEmpty && replies.isEmpty) else { continue }
            result.append(BangumiEpisodeComment(
                id: String(item.id),
                floor: floor,
                authorName: item.user?.displayName ?? "",
                avatarURL: item.user?.avatarURL,
                publishedAt: p1DateString(item.createdAt),
                body: body,
                imageURLs: images,
                replies: replies
            ))
        }
        return result
    }

    private static func isDeleted(_ item: P1EpisodeComment) -> Bool {
        item.state == 6 || item.state == 7
    }

    /// /p1 的正文是 BBCode：`[img]…[/img]` 拆成图片列表，其余当文本。
    /// 和网页抓取一样只收用户贴的图，`(bgm38)` 这类表情留在文本里。
    /// Regex 不是 Sendable，不能放 static；每次现建，正文很短，开销可忽略。
    private static func p1Body(_ content: String) -> (body: String, images: [URL]) {
        let p1ImageTag = /\[img\](.*?)\[\/img\]/.ignoresCase()
        var images: [URL] = []
        for match in content.matches(of: p1ImageTag) {
            let raw = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: raw) { images.append(url) }
        }
        let body = content.replacing(p1ImageTag, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, images)
    }

    /// 和网页上的时间形态对齐（`2024-4-9 22:20`）。
    private static func p1DateString(_ unix: Int?) -> String {
        guard let unix, unix > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-M-d HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private struct EpisodesEnvelope: Decodable {
        let data: [BangumiEpisode]
    }

    private func searchSubjects(
        keyword: String,
        sort: BangumiSearchSort,
        limit: Int,
        offset: Int,
        filter: BangumiSearchFilter
    ) async throws -> [BangumiItem] {
        var components = URLComponents(
            url: apiDomain.appendingPathComponent("/v0/search/subjects"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &req)

        let body = SearchRequestBody(
            keyword: keyword,
            sort: sort.rawValue,
            filter: SearchRequestBody.Filter(filter: filter)
        )
        req.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(req)
        return try decodeSearch(data)
    }

    // MARK: - Legacy search channel

    /// 旧通道是 best-effort：它挂了不能影响 v0 的结果，也不能冒泡成用户可见的错误。
    /// 合法查询（`Fate/Zero` 之类）在旧接口上本来就会失败，用户不该看见。
    private func legacyItemsIfEligible(
        keyword: String,
        filter: BangumiSearchFilter,
        offset: Int
    ) async -> [BangumiItem] {
        guard offset == 0, !filter.hasNarrowingConstraints else { return [] }
        let sanitized = BangumiLegacySearch.sanitizeKeyword(keyword)
        guard !sanitized.isEmpty else { return [] }
        return (try? await legacySearch(keyword: sanitized)) ?? []
    }

    private func legacySearch(keyword: String) async throws -> [BangumiItem] {
        // 关键词是 path 的一部分，不是 query —— 不能用 appendingPathComponent（会二次转义）。
        guard
            let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            var components = URLComponents(
                string: apiDomain.absoluteString + "/search/subject/" + escaped
            )
        else {
            throw BangumiAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "responseGroup", value: "large"),
            URLQueryItem(name: "max_results", value: String(BangumiLegacySearch.maxPageSize)),
            URLQueryItem(name: "start", value: "0"),
        ]
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        let data = try await performOnce(req)

        // 出错时 HTTP 仍是 200，body 变成 `{"code":404,...}`。
        if let envelope = try? JSONDecoder().decode(BangumiLegacyErrorEnvelope.self, from: data) {
            throw BangumiAPIError.http(status: envelope.code)
        }
        do {
            let response = try JSONDecoder().decode(BangumiLegacySearchResponse.self, from: data)
            return response.list.map { $0.toBangumiItem() }
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    // MARK: - internals

    func applyHeaders(to req: inout URLRequest) {
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func makeAPIRequest(path: String) throws -> URLRequest {
        let url = apiDomain.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        return req
    }

    private func fetchWebHTML(path: String) async throws -> String {
        let url = webDomain.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data = try await perform(req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BangumiAPIError.decoding(message: "HTML decode failed")
        }
        return html
    }

    /// bgm.tv 偶发直接断连（实测 8 次请求中 2 次），一挂搜索页就清空结果弹错误。
    /// 只对网络层瞬时错误重试一次：http 状态码和解码失败重试没有意义，
    /// cancelled 重试则会违背调用方的取消意图。
    func perform(_ req: URLRequest) async throws -> Data {
        do {
            return try await performOnce(req)
        } catch BangumiAPIError.transport, BangumiAPIError.timeout {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { throw BangumiAPIError.cancelled }
            return try await performOnce(req)
        }
    }

    private func performOnce(_ req: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw BangumiAPIError.transport(message: "non-HTTP response")
            }
            guard (200...299).contains(http.statusCode) else {
                throw BangumiAPIError.http(status: http.statusCode)
            }
            return data
        } catch is CancellationError {
            throw BangumiAPIError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .timedOut { throw BangumiAPIError.timeout }
            if urlError.code == .cancelled { throw BangumiAPIError.cancelled }
            throw BangumiAPIError.transport(message: urlError.localizedDescription)
        }
    }

    /// next.bgm.tv 的形态：`{ "data": [{ "subject": {...} }] }`
    private func decodeTrending(_ data: Data) throws -> [BangumiItem] {
        do {
            let envelope = try JSONDecoder().decode(TrendingEnvelope.self, from: data)
            return envelope.data.map { $0.subject.withHeat($0.count ?? 0) }
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    /// api.bgm.tv 的形态：`{ "data": [{...}] }`
    private func decodeSearch(_ data: Data) throws -> [BangumiItem] {
        do {
            let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
            return envelope.data
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    private func parseComments(html: String) throws -> [BangumiSubjectComment] {
        let doc = try Kanna.HTML(html: html, encoding: .utf8)
        return doc.xpath("//div[@id='comment_box']/div[@class='item clearit']").compactMap { node -> BangumiSubjectComment? in
            let authorName = node.xpath(".//div[@class='text']//a[@class='l']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body = node.xpath(".//p[@class='comment']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !authorName.isEmpty, !body.isEmpty else { return nil }
            let avatarStyle = node.xpath(".//a[@class='avatar']/span").first?["style"] ?? ""
            let avatarURL = absoluteURL(fromStyleBackgroundImage: avatarStyle)
            let starClass = node.xpath(".//span[contains(@class,'starlight')]").first?["class"] ?? ""
            let greyNodes = Array(node.xpath(".//small[@class='grey']"))
            let stateLabel = greyNodes.indices.contains(0)
                ? (greyNodes[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                : ""
            let publishedAt = greyNodes.indices.contains(1)
                ? (greyNodes[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                : ""
            return BangumiSubjectComment(
                id: node["data-item-user"] ?? UUID().uuidString,
                authorName: authorName,
                avatarURL: avatarURL,
                stateLabel: stateLabel.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                ratingLabel: starClass.replacingOccurrences(of: "starlight ", with: ""),
                publishedAt: publishedAt.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                body: body
            )
        }
    }

    /// 单集页的吐槽是论坛楼层结构：`#comment_list` 的直接子 `div` 是主楼，
    /// 楼中楼挂在主楼的 `.topic_sub_reply` 里。
    private func parseEpisodeComments(html: String) throws -> [BangumiEpisodeComment] {
        let doc = try Kanna.HTML(html: html, encoding: .utf8)
        return doc.xpath("//div[@id='comment_list']/div[contains(@class,'row_reply')]")
            .compactMap { node -> BangumiEpisodeComment? in
                let authorName = node.xpath(".//div[@class='inner']/strong/a").first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let messageNode = node.xpath(".//div[contains(@class,'message')]").first
                let body = commentText(of: messageNode)
                let images = commentImageURLs(in: messageNode)
                guard !authorName.isEmpty, !(body.isEmpty && images.isEmpty) else { return nil }
                let (floor, publishedAt) = floorAndTime(of: node)
                return BangumiEpisodeComment(
                    id: node["id"] ?? UUID().uuidString,
                    floor: floor,
                    authorName: authorName,
                    avatarURL: avatarURL(in: node),
                    publishedAt: publishedAt,
                    body: body,
                    imageURLs: images,
                    replies: parseSubReplies(in: node)
                )
            }
    }

    private func parseSubReplies(in node: Kanna.XMLElement) -> [BangumiEpisodeComment] {
        node.xpath(".//div[contains(@class,'topic_sub_reply')]/div[contains(@class,'sub_reply_bg')]")
            .compactMap { sub -> BangumiEpisodeComment? in
                let authorName = sub.xpath(".//div[@class='inner']/strong/a").first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let messageNode = sub.xpath(".//div[contains(@class,'cmt_sub_content')]").first
                let body = commentText(of: messageNode)
                let images = commentImageURLs(in: messageNode)
                guard !authorName.isEmpty, !(body.isEmpty && images.isEmpty) else { return nil }
                let (floor, publishedAt) = floorAndTime(of: sub)
                return BangumiEpisodeComment(
                    id: sub["id"] ?? UUID().uuidString,
                    floor: floor,
                    authorName: authorName,
                    avatarURL: avatarURL(in: sub),
                    publishedAt: publishedAt,
                    body: body,
                    imageURLs: images
                )
            }
    }

    /// 形如「#2-1 - 2024-4-9 22:20」，破折号前是楼层、后面是时间。
    private func floorAndTime(of node: Kanna.XMLElement) -> (floor: String, publishedAt: String) {
        let meta = node.xpath(".//div[@class='action']//small").first?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = meta.components(separatedBy: " - ")
        return (
            parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private func avatarURL(in node: Kanna.XMLElement) -> URL? {
        let style = node.xpath(".//a[@class='avatar']/span").first?["style"] ?? ""
        return absoluteURL(fromStyleBackgroundImage: style)
    }

    /// 楼层正文。`<br>` 是唯一的换行来源，直接取 `text` 会把几段话黏成一行。
    private func commentText(of node: Kanna.XMLElement?) -> String {
        guard let inner = node?.innerHTML else {
            return node?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let withBreaks = inner.replacingOccurrences(
            of: "<br[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        guard let fragment = try? Kanna.HTML(html: withBreaks, encoding: .utf8) else {
            return node?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return (fragment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 只收用户贴的图。表情是 `img.smile`，混进来会变成一屏小方块。
    private func commentImageURLs(in node: Kanna.XMLElement?) -> [URL] {
        guard let node else { return [] }
        return node.xpath(".//img").compactMap { img -> URL? in
            let classes = img["class"] ?? ""
            guard !classes.contains("smile") else { return nil }
            return absoluteURL(from: img["src"])
        }
    }

    private func parseReviews(html: String) throws -> [BangumiSubjectReview] {
        let doc = try Kanna.HTML(html: html, encoding: .utf8)
        return doc.xpath("//div[@id='entry_list']/div[@class='item clearit']").compactMap { node -> BangumiSubjectReview? in
            let titleNode = node.xpath(".//h2[@class='title']/a").first
            let title = titleNode?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let href = titleNode?["href"] ?? ""
            let summary = node.xpath(".//div[@class='content']/a").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let authorName = node.xpath(".//div[@class='time']/a[@class='l']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, !authorName.isEmpty else { return nil }
            let metaTexts = node.xpath(".//div[@class='time']").first?.text?
                .components(separatedBy: "·")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
            let avatarURL = absoluteURL(from: node.xpath(".//p[@class='cover']//img").first?["src"])
            return BangumiSubjectReview(
                id: href.isEmpty ? UUID().uuidString : href,
                title: title,
                authorName: authorName,
                avatarURL: avatarURL,
                publishedAt: metaTexts.dropFirst().first ?? "",
                replyCount: metaTexts.dropFirst(2).first ?? "",
                summary: summary,
                url: absoluteURL(from: href)
            )
        }
    }

    private func absoluteURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:" + value)
        }
        if value.hasPrefix("/") {
            return URL(string: value, relativeTo: webDomain)?.absoluteURL
        }
        return URL(string: value)
    }

    private func absoluteURL(fromStyleBackgroundImage value: String) -> URL? {
        guard let start = value.range(of: "url(")?.upperBound,
            let end = value.range(of: ")", range: start..<value.endIndex)?.lowerBound
        else {
            return nil
        }
        let raw = value[start..<end].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return absoluteURL(from: String(raw))
    }
}

// MARK: - Envelopes

/// next.<host>/p1 的列表外壳：`{ "data": [...], "total": n }`。
private struct P1ListEnvelope<Item: Decodable>: Decodable {
    let data: [Item]
}

private struct P1User: Decodable {
    let nickname: String?
    let username: String?
    let avatar: Avatar?

    struct Avatar: Decodable {
        let large: String?
        let medium: String?
        let small: String?
    }

    var displayName: String {
        let name = (nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (username ?? "") : name
    }

    var avatarURL: URL? {
        for candidate in [avatar?.large, avatar?.medium, avatar?.small] {
            if let candidate, !candidate.isEmpty, let url = URL(string: candidate) { return url }
        }
        return nil
    }
}

private struct P1SubjectComment: Decodable {
    let id: Int
    let user: P1User?
    /// 收藏状态：1 想看 2 看过 3 在看 4 搁置 5 抛弃。
    let type: Int?
    let rate: Int?
    let comment: String?
    let updatedAt: Int?
}

private struct P1Review: Decodable {
    let id: Int
    let user: P1User?
    let entry: Entry

    struct Entry: Decodable {
        let id: Int
        let title: String?
        let summary: String?
        let replies: Int?
        let createdAt: Int?
    }
}

private struct P1EpisodeComment: Decodable {
    let id: Int
    let content: String?
    let createdAt: Int?
    let state: Int?
    let user: P1User?
    let replies: [P1EpisodeComment]?
}

private struct TrendingEnvelope: Decodable {
    let data: [TrendingItem]
    struct TrendingItem: Decodable {
        let subject: BangumiItem
        /// 榜单热度，在 subject 外层，解码后回填进 item。
        let count: Int?
    }
}

private struct SearchEnvelope: Decodable {
    let data: [BangumiItem]
}

// MARK: - Request body

private struct SearchRequestBody: Encodable {
    let keyword: String
    let sort: String
    let filter: Filter

    struct Filter: Encodable {
        let type: [Int]
        let tag: [String]
        let rating: [String]?
        let air_date: [String]?
        let nsfw: Bool?

        init(filter: BangumiSearchFilter) {
            self.type = [2]
            self.tag = filter.tags

            var ratingExprs: [String] = []
            if let lo = filter.ratingMin { ratingExprs.append(">=\(Self.formatRating(lo))") }
            if let hi = filter.ratingMax { ratingExprs.append("<=\(Self.formatRating(hi))") }
            self.rating = ratingExprs.isEmpty ? nil : ratingExprs

            var airExprs: [String] = []
            if let lo = filter.airDateAfter { airExprs.append(">=\(lo)") }
            if let hi = filter.airDateBefore { airExprs.append("<\(hi)") }
            self.air_date = airExprs.isEmpty ? nil : airExprs

            // includeNSFW=false → 显式 nsfw:false
            // includeNSFW=true  → 不发 nsfw 字段
            //
            // 注意：这个字段在匿名请求下**不生效**。bgm 自己的 OpenAPI 原文是
            // 「无权限情况下忽略此选项，不会返回 NSFW 条目」—— 实测同一关键词
            // 传 true / false / 不传，total 完全一致。不登录时受限条目只能靠
            // `legacySearch` 那条旧接口通道召回。
            self.nsfw = filter.includeNSFW ? nil : false
        }

        private static func formatRating(_ value: Double) -> String {
            // 评分常见 0.5 step；渲染成 8.5 / 9 这类形态。
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", value)
            }
            return String(format: "%.1f", value)
        }

        enum CodingKeys: String, CodingKey {
            case type, tag, rating, air_date, nsfw
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encode(tag, forKey: .tag)
            if let rating { try c.encode(rating, forKey: .rating) }
            if let air_date { try c.encode(air_date, forKey: .air_date) }
            if let nsfw { try c.encode(nsfw, forKey: .nsfw) }
        }
    }
}

// MARK: - Errors

public enum BangumiAPIError: Error, Hashable, Sendable {
    case invalidURL
    case transport(message: String)
    case http(status: Int)
    case decoding(message: String)
    case timeout
    case cancelled

    public var userMessage: String {
        switch self {
        case .invalidURL: return "URL 无效"
        case .transport(let m): return "网络错误：\(m)"
        case .http(let s): return "HTTP \(s)"
        case .decoding: return "返回数据无法解析"
        case .timeout: return "请求超时"
        case .cancelled: return "已取消"
        }
    }
}
