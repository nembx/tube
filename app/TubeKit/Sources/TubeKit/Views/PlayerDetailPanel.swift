import Observation
import SwiftUI

/// 播放页详情面板的 tab。
enum PlayerDetailTab: String, CaseIterable, Hashable, Sendable {
    case episodes
    case comments

    var title: String {
        switch self {
        case .episodes: "选集"
        case .comments: "评论"
        }
    }
}

/// 面板顶部那段「当前这一集」的简介，取自 bgm 的分集接口。
enum PlayerEpisodeInfoState: Sendable {
    case idle
    case loading
    case loaded(BangumiEpisode)
    /// 没有 bangumi 条目、或者这一集在 bgm 上对不上号 —— 不是错误，就是没有。
    case unavailable(message: String)
    case failed(message: String)
}

enum PlayerCommentsState: Sendable {
    case idle
    case loading
    case loaded([BangumiEpisodeComment])
    /// 拿不到评论，但不是错误：没有 bangumi 条目、或者这一集在 bgm 上对不上号。
    case unavailable(message: String)
    case failed(message: String)
}

@MainActor
@Observable
final class PlayerDetailModel {
    private(set) var sources: [PlayableSource] = []
    private(set) var selectedSourceID: PlayableSource.ID?
    private(set) var selectedRoadIndex: Int = 0
    private(set) var sourceStates: [PlayableSource.ID: SourceEpisodesState] = [:]
    private(set) var isSearchingSources: Bool = false
    private(set) var sourceSearchFailed: String?
    private(set) var blockedSources: [BlockedSource] = []
    var activeCaptcha: CaptchaChallenge?
    /// 面板当前停在哪个 tab。播放页点「选集」时会直接把它拨到 `.episodes`。
    var tab: PlayerDetailTab = .episodes
    private(set) var commentsState: PlayerCommentsState = .idle
    private(set) var episodeInfoState: PlayerEpisodeInfoState = .idle
    /// 封面主色。面板底色跟着它走，和详情页 / 首页 banner 是同一套取色。
    private(set) var coverPalette: CoverColorPalette = .fallback

    private let searchCoordinator: SourceSearchCoordinating
    private let engine: RuleEngine
    private let api: BangumiAPIClientProtocol
    /// 条目的分集表拉一次就够，换集只换 episode id。
    private var bangumiEpisodes: [BangumiEpisode]?
    private var loadedInfoEpisodeIndex: Int?
    private var loadedCoverPalette = false
    private var loadedCommentsEpisodeIndex: Int?

    private var currentRequest: PlaybackRequest
    private var rules: [TubeRule]
    private var hasLoadedExtraSources: Bool = false

    init(
        currentRequest: PlaybackRequest,
        rules: [TubeRule],
        cachedSources: SourceSearchCache? = nil,
        searchCoordinator: SourceSearchCoordinating = SearchCoordinator(),
        engine: RuleEngine = LiveRuleEngine(),
        api: BangumiAPIClientProtocol = BangumiAPIClient.shared
    ) {
        self.currentRequest = currentRequest
        self.rules = rules
        self.searchCoordinator = searchCoordinator
        self.engine = engine
        self.api = api

        if let cache = cachedSources, !cache.sources.isEmpty {
            sources = cache.sources
            sourceStates = cache.sourceStates
            hasLoadedExtraSources = true
            let currentID = PlayableSource(
                result: SearchResult(
                    title: currentRequest.anime.title,
                    detailURL: currentRequest.anime.detailURL,
                    ruleName: currentRequest.rule.name
                )
            ).id
            selectedSourceID = currentID
            selectedRoadIndex = currentRequest.roadIndex
            sourceStates[currentID] = .loaded(currentRequest.anime)
        } else {
            syncCurrentRequest(currentRequest, rules: rules)
        }
    }

    func syncCurrentRequest(_ request: PlaybackRequest, rules: [TubeRule]) {
        // 换集就把这一集的简介和评论作废 —— 面板显示的必须是正在看的这一集。
        if loadedCommentsEpisodeIndex != request.episodeIndex {
            commentsState = .idle
        }
        if loadedInfoEpisodeIndex != request.episodeIndex {
            episodeInfoState = .idle
        }
        currentRequest = request
        self.rules = rules

        let currentSource = PlayableSource(
            result: SearchResult(
                title: request.anime.title,
                detailURL: request.anime.detailURL,
                ruleName: request.rule.name
            )
        )

        var nextSources = sources.filter { $0.id != currentSource.id }
        nextSources.insert(currentSource, at: 0)
        sources = nextSources

        sourceStates[currentSource.id] = .loaded(request.anime)
        selectedSourceID = currentSource.id
        selectedRoadIndex = request.roadIndex
    }

    func loadSourcesIfNeeded() async {
        guard !hasLoadedExtraSources else { return }
        hasLoadedExtraSources = true

        guard let item = currentRequest.item else {
            sourceSearchFailed = "当前播放入口没有番剧条目，仅可切换当前源的线路和剧集。"
            return
        }

        let remainingRules = rules.filter { $0.name != currentRequest.rule.name }
        guard !remainingRules.isEmpty else { return }

        isSearchingSources = true
        sourceSearchFailed = nil

        let currentResult = SearchResult(
            title: currentRequest.anime.title,
            detailURL: currentRequest.anime.detailURL,
            ruleName: currentRequest.rule.name
        )
        var candidates: [PlayableSource.ID: TitleMatcher.ScoredResult] = [
            PlayableSource(result: currentResult).id:
                TitleMatcher.ScoredResult(
                    result: currentResult,
                    score: 3,
                    season: TitleMatcher.season(of: currentResult.title),
                    seasonMatches: true
                )
        ]

        let keywords = searchKeywords(for: item)
        let expectedSeason = TitleMatcher.expectedSeason(
            displayName: item.displayName,
            name: item.name
        )
        let stream = searchCoordinator.searchAll(keywords: keywords, rules: remainingRules)
        for await update in stream {
            if case .ruleCaptchaRequired(let name, let url, let userAgent) = update {
                let reason = BlockedSource.Reason.captchaRequired(url: url, userAgent: userAgent)
                if let index = blockedSources.firstIndex(where: { $0.ruleName == name }) {
                    blockedSources[index] = BlockedSource(ruleName: name, reason: reason)
                } else {
                    blockedSources.append(BlockedSource(ruleName: name, reason: reason))
                }
                continue
            }
            if case .ruleResults(_, let results) = update {
                merge(
                    TitleMatcher.matches(
                        in: results,
                        keywords: keywords,
                        expectedSeason: expectedSeason
                    ),
                    into: &candidates
                )
            }
        }

        sources = PlayableSource.ranked(Array(candidates.values))
        isSearchingSources = false

        if sources.count == 1 {
            sourceSearchFailed = "没有搜索到其他可切换的播放源。"
        }
    }

    func selectSource(_ id: PlayableSource.ID) async {
        guard selectedSourceID != id || selectedDetail == nil else { return }
        guard let source = sources.first(where: { $0.id == id }) else { return }
        selectedSourceID = id
        selectedRoadIndex = 0

        if case .loaded(let detail) = sourceStates[id] {
            if detail.roads.indices.contains(currentRequest.roadIndex) {
                selectedRoadIndex = currentRequest.roadIndex
            }
            return
        }

        sourceStates[id] = .loading

        guard let rule = rules.first(where: { $0.name == source.ruleName }) else {
            sourceStates[id] = .failed(message: "未找到对应规则")
            return
        }

        do {
            let roads = try await engine.fetchEpisodes(detailURL: source.result.detailURL, with: rule)
            let detail = AnimeDetail(
                title: currentRequest.item?.displayName ?? currentRequest.anime.title,
                detailURL: source.result.detailURL,
                ruleName: source.ruleName,
                roads: roads
            )
            sourceStates[id] = .loaded(detail)
            if detail.roads.indices.contains(currentRequest.roadIndex) {
                selectedRoadIndex = currentRequest.roadIndex
            }
        } catch {
            sourceStates[id] = .failed(message: "\(error)")
        }
    }

    func selectRoad(_ index: Int) {
        selectedRoadIndex = index
    }

    func openCaptcha(for ruleName: String) {
        guard let blocked = blockedSources.first(where: { $0.ruleName == ruleName }) else { return }
        switch blocked.reason {
        case .captchaRequired(let url, let userAgent):
            activeCaptcha = CaptchaChallenge(ruleName: ruleName, url: url, userAgent: userAgent)
        }
    }

    func dismissCaptcha() {
        activeCaptcha = nil
    }

    func resolveCaptcha(_ challenge: CaptchaChallenge) async {
        activeCaptcha = nil
        blockedSources.removeAll { $0.ruleName == challenge.ruleName }
        guard let rule = rules.first(where: { $0.name == challenge.ruleName }),
            let item = currentRequest.item
        else { return }
        let keywords = searchKeywords(for: item)
        let expectedSeason = TitleMatcher.expectedSeason(
            displayName: item.displayName,
            name: item.name
        )
        let stream = searchCoordinator.searchAll(keywords: keywords, rules: [rule])
        var candidates: [PlayableSource.ID: TitleMatcher.ScoredResult] = Dictionary(
            uniqueKeysWithValues: sources.map {
                (
                    $0.id,
                    TitleMatcher.ScoredResult(
                        result: $0.result,
                        score: 3,
                        season: TitleMatcher.season(of: $0.result.title),
                        seasonMatches: $0.seasonMatches
                    )
                )
            }
        )
        for await update in stream {
            if case .ruleCaptchaRequired(let name, let url, let userAgent) = update {
                let reason = BlockedSource.Reason.captchaRequired(url: url, userAgent: userAgent)
                if let index = blockedSources.firstIndex(where: { $0.ruleName == name }) {
                    blockedSources[index] = BlockedSource(ruleName: name, reason: reason)
                } else {
                    blockedSources.append(BlockedSource(ruleName: name, reason: reason))
                }
                continue
            }
            if case .ruleResults(_, let results) = update {
                merge(
                    TitleMatcher.matches(
                        in: results,
                        keywords: keywords,
                        expectedSeason: expectedSeason
                    ),
                    into: &candidates
                )
            }
        }
        sources = PlayableSource.ranked(Array(candidates.values))
    }

    @discardableResult
    private func merge(
        _ scored: [TitleMatcher.ScoredResult],
        into candidates: inout [PlayableSource.ID: TitleMatcher.ScoredResult]
    ) -> Bool {
        var changed = false
        for candidate in scored {
            let id = PlayableSource(result: candidate.result).id
            if let existing = candidates[id], existing.score >= candidate.score { continue }
            candidates[id] = candidate
            changed = true
        }
        return changed
    }

    /// 播放源按规则名合并后的展示顺序。
    var sourceGroups: [SourceGroup] {
        PlayableSource.grouped(sources)
    }

    var selectedSource: PlayableSource? {
        guard let selectedSourceID else { return sources.first }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    var selectedSourceState: SourceEpisodesState {
        guard let selectedSource else { return .idle }
        return sourceStates[selectedSource.id] ?? .idle
    }

    var selectedDetail: AnimeDetail? {
        guard let selectedSource else { return nil }
        if case .loaded(let detail) = sourceStates[selectedSource.id] {
            return detail
        }
        return nil
    }

    var currentEpisodes: [Episode] {
        guard let detail = selectedDetail, detail.roads.indices.contains(selectedRoadIndex) else {
            return []
        }
        return detail.roads[selectedRoadIndex].episodes
    }

    func playbackRequest(episodeIndex: Int) -> PlaybackRequest? {
        guard let detail = selectedDetail,
            let source = selectedSource,
            let rule = rules.first(where: { $0.name == source.ruleName }),
            detail.roads.indices.contains(selectedRoadIndex),
            detail.roads[selectedRoadIndex].episodes.indices.contains(episodeIndex)
        else {
            return nil
        }

        return PlaybackRequest(
            anime: detail,
            roadIndex: selectedRoadIndex,
            episodeIndex: episodeIndex,
            rule: rule,
            item: currentRequest.item
        )
    }

    var currentItem: BangumiItem? { currentRequest.item }

    var currentEpisodeIndex: Int { currentRequest.episodeIndex }

    /// 取封面主色给面板做底色。小图通常在别处已经缓存过，几乎瞬时。
    func loadCoverPaletteIfNeeded() async {
        guard !loadedCoverPalette, let item = currentRequest.item else { return }
        loadedCoverPalette = true
        let candidates = [
            item.images.grid,
            item.images.small,
            item.images.medium,
            item.images.common,
            item.images.large,
        ]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { continue }
            if let extracted = await CoverColorExtractor.loadAndExtract(from: url) {
                coverPalette = extracted
                return
            }
        }
    }

    /// 拉当前这一集在 bgm 上的信息（标题 / 时长 / 首播 / 简介）。同一集只拉一次。
    func loadEpisodeInfoIfNeeded() async {
        guard loadedInfoEpisodeIndex != currentRequest.episodeIndex else { return }
        let episodeIndex = currentRequest.episodeIndex
        loadedInfoEpisodeIndex = episodeIndex
        episodeInfoState = .loading
        do {
            guard let episode = try await bangumiEpisode(at: episodeIndex) else { return }
            guard loadedInfoEpisodeIndex == episodeIndex else { return }
            episodeInfoState = .loaded(episode)
        } catch {
            loadedInfoEpisodeIndex = nil
            episodeInfoState = .failed(message: Self.message(for: error, what: "分集信息"))
        }
    }

    /// 拉当前这一集在 bgm 上的吐槽。同一集只拉一次，换集由 `syncCurrentRequest` 作废。
    func loadCommentsIfNeeded() async {
        guard loadedCommentsEpisodeIndex != currentRequest.episodeIndex else { return }
        let episodeIndex = currentRequest.episodeIndex
        loadedCommentsEpisodeIndex = episodeIndex
        commentsState = .loading
        do {
            guard let episode = try await bangumiEpisode(at: episodeIndex) else {
                if case .unavailable(let message) = episodeInfoState {
                    commentsState = .unavailable(message: message)
                }
                return
            }
            let comments = try await api.fetchEpisodeComments(episodeID: episode.id)
            // 拉的过程中用户可能已经换集，晚到的结果不能盖上去。
            guard loadedCommentsEpisodeIndex == episodeIndex else { return }
            commentsState = .loaded(comments)
        } catch {
            // 失败不锁住这一集，用户点重试还能再来一次。
            loadedCommentsEpisodeIndex = nil
            commentsState = .failed(message: Self.message(for: error, what: "这一集的吐槽"))
        }
    }

    /// 播放器的第 N 集对应 bgm 的哪一集。对不上或者压根没有条目时写进
    /// `episodeInfoState` 并返回 nil —— 调用方据此收摊，不要再发第二个请求。
    private func bangumiEpisode(at episodeIndex: Int) async throws -> BangumiEpisode? {
        guard let item = currentRequest.item, item.id > 0 else {
            // 从「继续观看」进来的播放请求只带着标题和封面，没有 bangumi 条目号。
            episodeInfoState = .unavailable(message: "这次播放没有关联 bangumi 条目，拿不到分集信息。")
            return nil
        }
        let episodes: [BangumiEpisode]
        if let bangumiEpisodes {
            episodes = bangumiEpisodes
        } else {
            episodes = try await api.fetchEpisodes(subjectID: item.id)
            bangumiEpisodes = episodes
        }
        guard let episode = BangumiEpisode.match(episodeIndex: episodeIndex, in: episodes) else {
            episodeInfoState = .unavailable(message: "bgm 上没有对应这一集的记录。")
            return nil
        }
        return episode
    }

    func reloadComments() async {
        loadedCommentsEpisodeIndex = nil
        await loadCommentsIfNeeded()
    }

    func reloadEpisodeInfo() async {
        loadedInfoEpisodeIndex = nil
        await loadEpisodeInfoIfNeeded()
    }

    private static func message(for error: Error, what: String) -> String {
        if let apiError = error as? BangumiAPIError {
            return "\(what)拉取失败：\(apiError.userMessage)"
        }
        return "\(what)拉取失败：\(error)"
    }

    private func searchKeywords(for item: BangumiItem) -> [String] {
        TitleMatcher.searchKeywords(
            displayName: item.displayName,
            name: item.name,
            aliases: item.infoboxValue(forAnyOf: ["别名"]).map(TitleMatcher.splitAliases) ?? []
        )
    }
}


/// 「回到顶部」露不露面这件事。抽出来是为了让面板只在阈值被跨过时改一次 state ——
/// 滚动位移本身每帧都在变，直接存进 `@State` 会让整个面板每帧重算一遍。
enum PlayerDetailScrollChrome {
    /// 滚过大半屏才值得给一个回顶按钮，不然它总在那儿碍事。
    static let backToTopThreshold: CGFloat = 240

    static func showsBackToTop(scrollOffset: CGFloat) -> Bool {
        scrollOffset > backToTopThreshold
    }
}

/// 播放页的详情面板：单集简介常驻顶部，下面是选集 / 评论两个 tab。
///
/// 三种摆法共用这一个视图 —— 宽屏是播放器右侧的可收起侧栏，手机竖屏是播放器下方
/// 的常驻区域，手机横屏不出现。配色和详情页同一套（`ContentPalette`）：底色由封面
/// 主色驱动，深浅跟随系统，不再是一层写死的白字玻璃。
struct PlayerDetailPanel: View {
    @Bindable var model: PlayerDetailModel
    let activeRequest: PlaybackRequest
    /// 常驻摆法（手机竖屏）传 nil —— 没有「关掉面板」这回事。
    let onClose: (() -> Void)?
    let onSelectRequest: (PlaybackRequest) -> Void
    /// 点开评论里的图。交给播放页整窗铺开 —— 面板自己弹 sheet 的话，
    /// mac 上只有一个小窗，看不清图。
    let onPreviewImage: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// 用户手动点过的分段。nil 表示跟着正在播的那一集走 ——
    /// 看到 1178 集时打开面板，段签该停在 1101-1200 而不是 1-100。
    @State private var episodePage: Int?
    @State private var isSummaryExpanded: Bool = false
    /// 「回到顶部」露不露面。只在阈值被跨过时翻一次，不跟着每帧的滚动位移走。
    @State private var showsBackToTop: Bool = false

    private static let topAnchor = "player-detail-top"
    private static let scrollSpace = "player-detail-scroll"

    private static func episodeAnchor(_ index: Int) -> String {
        "player-detail-episode-\(index)"
    }

    private var palette: ContentPalette {
        ContentPalette.make(for: colorScheme, cover: model.coverPalette)
    }

    /// 网格里「正在播」的那一格的下标。选中的源 / 线路和正在播的不是同一路时没有这一格。
    private var currentGridEpisodeIndex: Int? {
        let index = activeRequest.episodeIndex
        guard let request = model.playbackRequest(episodeIndex: index),
            request.rule.name == activeRequest.rule.name,
            request.roadIndex == activeRequest.roadIndex
        else {
            return nil
        }
        return index
    }

    /// 网格该滚到哪一格。当前段里没有正在播的那一集（用户翻到了别的段）时不滚。
    private var episodeScrollTarget: String? {
        guard model.tab == .episodes, let index = currentGridEpisodeIndex else { return nil }
        let range = EpisodePagination.range(
            page: effectiveEpisodePage,
            episodeCount: model.currentEpisodes.count
        )
        guard range.contains(index) else { return nil }
        return Self.episodeAnchor(index)
    }

    /// 当前该显示的分段。用户点过段签就听他的，否则跟着正在播的那一集。
    private var effectiveEpisodePage: Int {
        if let episodePage {
            return min(
                max(episodePage, 0),
                EpisodePagination.pageCount(episodeCount: model.currentEpisodes.count) - 1
            )
        }
        return EpisodePagination.page(
            containing: currentGridEpisodeIndex ?? 0,
            episodeCount: model.currentEpisodes.count
        )
    }

    var body: some View {
        let palette = palette

        // 整个面板一起滚：标题和单集简介占掉大半高度时，
        // 只让 tab 下面那块滚的话，剩给剧集和评论的可视区只有一两行。
        // tab 栏钉在顶上，滚多远都还能换 tab。
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)

                    header(palette)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                    Section {
                        // 内容不套一层 VStack：评论要按行摆进 LazyVStack 里，
                        // 包起来的话这一整屏评论会被一次性布局出来。
                        content(palette)
                    } header: {
                        tabBar(palette)
                            .padding(.horizontal, 18)
                            .padding(.top, 14)
                            .padding(.bottom, 12)
                            // 钉住之后底下的内容会从它身后穿过去，得有不透明底色挡着。
                            .background(palette.background)
                    }
                }
                .background {
                    // 量滚动位移：内容顶边相对滚动容器往上跑了多少。
                    GeometryReader { geo in
                        Color.clear
                            .onChange(
                                of: geo.frame(in: .named(Self.scrollSpace)).minY,
                                initial: true
                            ) { _, minY in
                                let shows = PlayerDetailScrollChrome
                                    .showsBackToTop(scrollOffset: -minY)
                                if shows != showsBackToTop {
                                    showsBackToTop = shows
                                }
                            }
                    }
                }
            }
            .coordinateSpace(.named(Self.scrollSpace))
            .overlay(alignment: .bottomTrailing) {
                if showsBackToTop {
                    backToTopButton(palette) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scroller.scrollTo(Self.topAnchor, anchor: .top)
                        }
                    }
                    .padding(.trailing, 18)
                    // 竖屏时面板一直铺到屏幕底边，得给 home indicator 让位。
                    .padding(.bottom, 28)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: showsBackToTop)
            // 剧集一到位就把网格挪到正在播的那一集上；当前段里没有这一格时不动。
            .onChange(of: episodeScrollTarget, initial: true) { _, target in
                guard let target else { return }
                scroller.scrollTo(target, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
        // 关闭键钉在右上角：内容滚起来之后，用户不该为了关面板先滚回顶部。
        .overlay(alignment: .topTrailing) {
            if let onClose {
                closeButton(palette, action: onClose)
                    .padding(.trailing, 14)
                    .padding(.top, 12)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: model.coverPalette)
        // 换集之后段签重新跟着当前集走。
        .onChange(of: activeRequest.episodeIndex) { _, _ in episodePage = nil }
        .task {
            await model.loadCoverPaletteIfNeeded()
        }
        .task {
            await model.loadSourcesIfNeeded()
        }
        .task(id: model.currentEpisodeIndex) {
            // 简介常驻在顶部，进面板 / 换集就拉，不等用户点 tab。
            await model.loadEpisodeInfoIfNeeded()
            guard model.tab == .comments else { return }
            await model.loadCommentsIfNeeded()
        }
        .task(id: model.tab) {
            guard model.tab == .comments else { return }
            await model.loadCommentsIfNeeded()
        }
        .sheet(item: Binding(
            get: { model.activeCaptcha },
            set: { model.activeCaptcha = $0 }
        )) { challenge in
            CaptchaVerificationSheet(
                url: challenge.url,
                ruleName: challenge.ruleName,
                userAgent: challenge.userAgent
            ) {
                Task { await model.resolveCaptcha(challenge) }
            }
        }
    }

    // MARK: - 顶部

    /// 卡片的圆角与描边：整块面板用同一套分组卡片语言（系统设置的 inset grouped 那种）。
    private static let cardRadius: CGFloat = 16

    private func cardShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
    }

    @ViewBuilder
    private func card<Content: View>(_ palette: ContentPalette, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(palette.surface, in: cardShape())
            .overlay {
                cardShape().strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    /// 「正在播放」卡：动态波形图标做状态标，番名、本集名、时长 / 首播分三级字重，
    /// 简介收在同一张卡的下半截。原来这几行是散落在底色上的裸文本，没有层级。
    @ViewBuilder
    private func header(_ palette: ContentPalette) -> some View {
        card(palette) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        Text("正在播放")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textTertiary)

                    Text(activeRequest.anime.title)
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    episodeHeadline(palette)
                }
                // 右上角是钉住的关闭键，标题不能压到它下面。
                .padding(.trailing, onClose == nil ? 0 : 36)
                .padding(16)

                episodeDescription(palette)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 本集名 + 时长 / 首播。简介还没拉到时用占位，不让卡片高度来回跳。
    @ViewBuilder
    private func episodeHeadline(_ palette: ContentPalette) -> some View {
        switch model.episodeInfoState {
        case .idle, .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在拉取本集信息…")
            }
            .font(.subheadline)
            .foregroundStyle(palette.textTertiary)
        case .unavailable:
            Text(activeRequest.episode.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.textSecondary)
        case .failed(let message):
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试") {
                    Task { await model.reloadEpisodeInfo() }
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            }
        case .loaded(let episode):
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.displayHeadline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !metaLine(for: episode).isEmpty {
                    Text(metaLine(for: episode))
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    /// 简介：卡片下半截，和上面用一条内缩的细线分开；「展开」是带角标的小按钮。
    @ViewBuilder
    private func episodeDescription(_ palette: ContentPalette) -> some View {
        if case .loaded(let episode) = model.episodeInfoState, !episode.desc.isEmpty {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(episode.desc)
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(isSummaryExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSummaryExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(isSummaryExpanded ? "收起" : "展开")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isSummaryExpanded ? 180 : 0))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private func metaLine(for episode: BangumiEpisode) -> String {
        var parts: [String] = []
        if !episode.duration.isEmpty { parts.append("时长 \(episode.duration)") }
        if !episode.airDate.isEmpty { parts.append("首播 \(episode.airDate)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func closeButton(_ palette: ContentPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(palette.surfaceRaised)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起详情")
    }

    @ViewBuilder
    private func backToTopButton(
        _ palette: ContentPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.footnote.weight(.bold))
                Text("回到顶部")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                Capsule(style: .continuous)
                    .fill(palette.backgroundRaised)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到顶部")
    }

    /// 系统分段控件。两个 tab 是并列的互斥视图，这正是 segmented control 的本职。
    @ViewBuilder
    private func tabBar(_ palette: ContentPalette) -> some View {
        Picker("", selection: $model.tab) {
            ForEach(PlayerDetailTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private func content(_ palette: ContentPalette) -> some View {
        switch model.tab {
        case .episodes:
            VStack(alignment: .leading, spacing: 20) {
                sourceAndLineRow(palette)
                episodesSection(palette)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .comments:
            commentsSection(palette)
        }
    }

    // MARK: - 选集

    /// 播放源和线路做成一张分组卡里的两行（系统设置那种列表行），点行弹菜单。
    ///
    /// 这两样本来就是「选一个」而不是「浏览一遍」，收成菜单最贴合；行式布局把字段名、
    /// 当前值、可切换的角标按固定位置摆开，比胶囊里挤一串字清楚。
    @ViewBuilder
    private func sourceAndLineRow(_ palette: ContentPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            card(palette) {
                VStack(spacing: 0) {
                    sourceMenu(palette)
                    if showsLineMenu {
                        Rectangle()
                            .fill(palette.hairline)
                            .frame(height: 1)
                            .padding(.leading, 46)
                        lineMenu(palette)
                    }
                }
            }

            // 卡片下面的脚注：同一站点下选的是哪个条目、搜索进度、错误。
            VStack(alignment: .leading, spacing: 6) {
                if model.isSearchingSources {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在搜索更多播放源…")
                    }
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                }
                if let selected = model.selectedSource, selected.variantLabel != selected.ruleName {
                    Text("当前条目 · \(selected.variantLabel)")
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                if let message = model.sourceSearchFailed {
                    hint(message, palette)
                }
                if case .failed(let message) = model.selectedSourceState {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// 只有一条线路时不摆 —— 一个只能选当前项的菜单没有意义。
    private var showsLineMenu: Bool {
        if case .loaded(let detail) = model.selectedSourceState { return detail.roads.count > 1 }
        return false
    }

    @ViewBuilder
    private func sourceMenu(_ palette: ContentPalette) -> some View {
        Menu {
            ForEach(model.sourceGroups) { group in
                if group.sources.count == 1, let only = group.sources.first {
                    Button {
                        Task { await model.selectSource(only.id) }
                    } label: {
                        menuItemLabel(group.ruleName, isSelected: only.id == model.selectedSourceID)
                    }
                } else {
                    Menu(group.ruleName) {
                        ForEach(group.sources) { source in
                            Button {
                                Task { await model.selectSource(source.id) }
                            } label: {
                                menuItemLabel(
                                    source.variantLabel,
                                    isSelected: source.id == model.selectedSourceID
                                )
                            }
                        }
                    }
                }
            }

            if !model.blockedSources.isEmpty {
                Section("需要人机校验") {
                    ForEach(model.blockedSources) { blocked in
                        Button {
                            model.openCaptcha(for: blocked.ruleName)
                        } label: {
                            Label(blocked.ruleName, systemImage: "lock")
                        }
                    }
                }
            }
        } label: {
            settingRow(
                title: "播放源",
                value: model.selectedSource?.ruleName ?? "未选择",
                systemImage: "square.stack.3d.up",
                palette: palette
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(model.sourceGroups.isEmpty && model.blockedSources.isEmpty)
    }

    @ViewBuilder
    private func lineMenu(_ palette: ContentPalette) -> some View {
        if case .loaded(let detail) = model.selectedSourceState, detail.roads.count > 1 {
            let current = detail.roads.indices.contains(model.selectedRoadIndex)
                ? detail.roads[model.selectedRoadIndex].label
                : detail.roads[0].label

            Menu {
                ForEach(detail.roads.indices, id: \.self) { index in
                    Button {
                        model.selectRoad(index)
                        episodePage = nil
                    } label: {
                        menuItemLabel(
                            detail.roads[index].label,
                            isSelected: model.selectedRoadIndex == index
                        )
                    }
                }
            } label: {
                settingRow(
                    title: "线路",
                    value: current,
                    systemImage: "arrow.triangle.branch",
                    palette: palette
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    /// 选中项前面打勾 —— 菜单里没有别的地方能表达当前值。
    @ViewBuilder
    private func menuItemLabel(_ text: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    /// 设置风格的列表行：左图标 + 字段名，右侧当前值 + 「可切换」角标。
    private func settingRow(
        title: String,
        value: String,
        systemImage: String,
        palette: ContentPalette
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22)

            Text(title)
                .font(.body)
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func episodesSection(_ palette: ContentPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("选集", palette)
                Spacer()
                if case .loaded = model.selectedSourceState, !model.currentEpisodes.isEmpty {
                    Text("共 \(model.currentEpisodes.count) 集")
                        .font(.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            switch model.selectedSourceState {
            case .idle:
                hint("请选择一个播放源。", palette)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在拉取剧集…")
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                }
            case .failed:
                hint("当前播放源暂时不可用。", palette)
            case .loaded:
                episodeGrid(palette)
            }
        }
        .onChange(of: model.selectedRoadIndex) { _, _ in episodePage = nil }
        .onChange(of: model.selectedSourceID) { _, _ in episodePage = nil }
    }

    @ViewBuilder
    private func episodeGrid(_ palette: ContentPalette) -> some View {
        let episodes = model.currentEpisodes
        let pageSize = EpisodePagination.pageSize
        let totalPages = EpisodePagination.pageCount(episodeCount: episodes.count)
        let safePage = effectiveEpisodePage
        let pageRange = EpisodePagination.range(page: safePage, episodeCount: episodes.count)
        let pageStart = pageRange.lowerBound
        let pageEnd = pageRange.upperBound

        // 分段签横滚，不换行 —— 百集以上的番有十几段，铺开会把网格顶下去。
        if totalPages > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        let start = page * pageSize + 1
                        let end = min((page + 1) * pageSize, episodes.count)
                        Button {
                            episodePage = page
                        } label: {
                            pill("\(start)-\(end)", isSelected: safePage == page, palette: palette)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }

        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 10)],
            spacing: 10
        ) {
            ForEach(Array(episodes[pageStart..<pageEnd].enumerated()), id: \.element.id) { pageIndex, episode in
                let absoluteIndex = pageStart + pageIndex
                let request = model.playbackRequest(episodeIndex: absoluteIndex)
                let isCurrent =
                    request?.rule.name == activeRequest.rule.name &&
                    request?.roadIndex == activeRequest.roadIndex &&
                    request?.episodeIndex == activeRequest.episodeIndex

                Button {
                    if let request {
                        onSelectRequest(request)
                    }
                } label: {
                    episodeCell(episode, isCurrent: isCurrent, palette: palette)
                }
                .buttonStyle(.plain)
                .id(Self.episodeAnchor(absoluteIndex))
            }
        }
    }

    /// 剧集格：正在播的那一格实心强调并带播放图标，其它格浅底细描边。
    /// 强调色沿用全 App 的单色体系（浅色黑 / 深色白），和详情页的播放键一致。
    private func episodeCell(_ episode: Episode, isCurrent: Bool, palette: ContentPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let fill = TubeMonochrome.fill(for: colorScheme)
        return VStack(spacing: 4) {
            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
            }
            Text(episode.title)
                .font(.subheadline.weight(isCurrent ? .bold : .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(isCurrent ? TubeMonochrome.onFill(for: colorScheme) : palette.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isCurrent ? fill : palette.surface, in: shape)
        .overlay {
            shape.strokeBorder(isCurrent ? Color.clear : palette.hairline, lineWidth: 1)
        }
        .contentShape(shape)
        .animation(.easeOut(duration: 0.18), value: isCurrent)
    }

    // MARK: - 评论

    /// 评论区里非列表的那几种状态（加载中 / 失败 / 空）共用的边距。
    private struct CommentsBlockInsets: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 评论按行直接摆进外层 LazyVStack：一集几百条吐槽时，
    /// 包在一个 VStack 里会被整体布局，滚动就废了。
    @ViewBuilder
    private func commentsSection(_ palette: ContentPalette) -> some View {
        switch model.commentsState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在拉取这一集的吐槽…")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            }
            .modifier(CommentsBlockInsets())
        case .unavailable(let message):
            hint(message, palette)
                .modifier(CommentsBlockInsets())
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试") {
                    Task { await model.reloadComments() }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(palette.surfaceRaised, in: Capsule(style: .continuous))
            }
            .modifier(CommentsBlockInsets())
        case .loaded(let comments):
            if comments.isEmpty {
                hint("这一集还没有人吐槽。", palette)
                    .modifier(CommentsBlockInsets())
            } else {
                ForEach(comments) { comment in
                    commentRow(comment, palette: palette)
                        // 分隔线画在每行底边，末行不画。
                        .overlay(alignment: .bottom) {
                            if comment.id != comments.last?.id {
                                Rectangle()
                                    .fill(palette.hairline)
                                    .frame(height: 1)
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Color.clear
                    .frame(height: 24)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: BangumiEpisodeComment, palette: ContentPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentBody(comment, avatarSize: 34, isReply: false, palette: palette)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comment.replies) { reply in
                        commentBody(reply, avatarSize: 26, isReply: true, palette: palette)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 2)
                // 楼中楼靠一条竖线挂在主楼下面，不用再缩进一层背景。
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(palette.hairline)
                        .frame(width: 2)
                }
                .padding(.leading, 44)
            }
        }
        // 分隔线画在行的底边，这层留白同时是上下两行之间的间距。
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func commentBody(
        _ comment: BangumiEpisodeComment,
        avatarSize: CGFloat,
        isReply: Bool,
        palette: ContentPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImage(url: comment.avatarURL) {
                palette.surface
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if !comment.floor.isEmpty {
                        Text(comment.floor)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 4)
                    Text(comment.publishedAt)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }

                if !comment.body.isEmpty {
                    Text(comment.body)
                        .font(isReply ? .callout : .body)
                        .foregroundStyle(palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(comment.imageURLs, id: \.self) { url in
                    Button {
                        onPreviewImage(url)
                    } label: {
                        RemoteImage(url: url) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.surface)
                                .frame(height: 120)
                        }
                        .frame(maxWidth: 260, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看大图")
                }
            }
        }
    }

    // MARK: - 小件

    @ViewBuilder
    private func sectionTitle(_ text: String, _ palette: ContentPalette) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(palette.textPrimary)
    }

    @ViewBuilder
    private func hint(_ text: String, _ palette: ContentPalette) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func pill(_ text: String, isSelected: Bool, palette: ContentPalette) -> some View {
        Text(text)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? palette.surfaceRaised : palette.surface)
            }
            .contentShape(Capsule(style: .continuous))
    }
}

/// 评论里的图点开看大图：铺满整个播放窗口，双指缩放，点背景或按钮关掉。
struct CommentImagePreview: View {
    let url: URL
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            RemoteImage(url: url) {
                ProgressView()
            }
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        // 放到 5 倍够看清一张贴图了，再大只会糊。
                        scale = min(max(committedScale * value, 1), 5)
                    }
                    .onEnded { _ in
                        committedScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scale = scale > 1 ? 1 : 2
                    committedScale = scale
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Circle()
                            .fill(.primary.opacity(0.16))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "xmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭大图")
                }
                Spacer()
            }
            .padding(16)
        }
        // 不设固定尺寸：由播放页把它铺满整窗，mac 上不再是一个小方框。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // 大图始终是深色底，前景交给系统 —— 和播放控件同一套规矩。
        .environment(\.colorScheme, .dark)
    }
}
