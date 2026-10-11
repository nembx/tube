import SwiftUI

// MARK: - Regular (wide) detail chrome
//
// 影院式详情页：全幅 hero（封面模糊底 + 原比例海报 + 排版信息），下面是双栏内容区。
// 窄屏走 `DetailView`；两边共用 `DetailViewModel`，chrome 分开维护。

/// 宽屏详情页的布局参数。纯函数，方便测。
enum RegularDetailLayout {
    /// Hero 吃掉视口，底部留一条“下面还有东西”的提示高度。
    static let heroBottomPeek: CGFloat = 132
    /// 高度下限 = 海报 + 信息栏排下来需要的高度（含顶部让位）。
    static let heroMinHeight: CGFloat = 520
    static let heroMaxHeight: CGFloat = 880
    /// 低于这个高度走精简版：收起原名和简介。
    static let heroCompactThreshold: CGFloat = 620
    /// 二级页没有悬浮顶栏，但要让开 macOS 交通灯和系统返回键。
    static let heroTopInset: CGFloat = 72

    static let horizontalPadding: CGFloat = 56
    static let posterGap: CGFloat = 44
    static let heroTextMaxWidth: CGFloat = 640

    /// 海报按封面原比例（3:4）摆放，不做任何拉伸。
    static let posterAspectRatio: CGFloat = 3.0 / 4.0
    static let posterHeightRatio: CGFloat = 0.56
    static let posterMinHeight: CGFloat = 280
    /// 上限压在 440：源图短边约 1000px，@2x 下 440pt = 880px，还在原图以内。
    static let posterMaxHeight: CGFloat = 440
    static let posterCornerRadius: CGFloat = 12
    static let posterFrameInset: CGFloat = 6
    /// 窗口窄到这个宽度以下就不摆海报，把宽度全留给信息栏。
    static let posterMinimumWindowWidth: CGFloat = 900

    /// 背景是**这张封面本身**放大后模糊出来的，与首页 hero 同一套做法。
    static let backdropBlurRadius: CGFloat = 30
    /// 模糊会把边缘吸淡，背景要超铺一圈盖住。
    static let backdropOverscan: CGFloat = 1.3
    static let backdropDim: Double = 0.46
    static let glowCenter = UnitPoint(x: 0.24, y: 0.42)
    static let glowRadiusRatio: CGFloat = 0.9
    static let glowOpacity: Double = 0.24

    /// 正文最大宽度。再宽读起来就要转头了。
    static let contentMaxWidth: CGFloat = 1240
    /// 右侧资料栏固定宽 —— 它装的是标签值对，宽度浮动只会让对齐变差。
    static let sideColumnWidth: CGFloat = 320
    static let columnGap: CGFloat = 40
    /// 主栏窄于这个宽度就不分栏了：剧集宫格挤成两列比资料栏更亏。
    static let mainColumnMinimumWidth: CGFloat = 520

    static let moduleRadius: CGFloat = 18
    static let chipRadius: CGFloat = 10
    static let episodeMin: CGFloat = 92
    /// 标签云上限 —— Bangumi 有些条目挂了 40+ 个标签。
    static let maxTagChips: Int = 24
    static let characterMin: CGFloat = 120
    static let characterMax: CGFloat = 168
    static let characterSpacing: CGFloat = 14
    /// 角色立绘比例（竖图），宽度随列宽走，高度按比例自适应。
    static let characterImageAspect: CGFloat = 3.0 / 4.0

    static func heroHeight(viewportHeight: CGFloat) -> CGFloat {
        min(heroMaxHeight, max(heroMinHeight, viewportHeight - heroBottomPeek))
    }

    static func isCompactHero(heroHeight: CGFloat) -> Bool {
        heroHeight < heroCompactThreshold
    }

    static func posterHeight(heroHeight: CGFloat) -> CGFloat {
        min(posterMaxHeight, max(posterMinHeight, heroHeight * posterHeightRatio))
    }

    static func posterWidth(heroHeight: CGFloat) -> CGFloat {
        posterHeight(heroHeight: heroHeight) * posterAspectRatio
    }

    static func showsPoster(width: CGFloat) -> Bool {
        width >= posterMinimumWindowWidth
    }

    /// 信息栏可用宽度：先给海报连相框留够，剩下的再夹到可读上限。
    static func heroTextWidth(width: CGFloat, heroHeight: CGFloat) -> CGFloat {
        let bare = max(240, width - horizontalPadding * 2)
        guard showsPoster(width: width) else {
            return min(heroTextMaxWidth, bare)
        }
        let available = bare
            - posterWidth(heroHeight: heroHeight)
            - posterFrameInset * 2
            - posterGap
        return min(heroTextMaxWidth, max(240, available))
    }

    static func contentWidth(viewportWidth: CGFloat) -> CGFloat {
        max(280, min(contentMaxWidth, viewportWidth) - horizontalPadding * 2)
    }

    /// 概览是否分栏：主栏留不够宽就退回单栏。
    static func isTwoColumn(contentWidth: CGFloat) -> Bool {
        contentWidth - sideColumnWidth - columnGap >= mainColumnMinimumWidth
    }

    static func mainColumnWidth(contentWidth: CGFloat) -> CGFloat {
        guard isTwoColumn(contentWidth: contentWidth) else { return contentWidth }
        return contentWidth - sideColumnWidth - columnGap
    }
}

private enum RegularDetailStyle {
    static let cornerRadius: CGFloat = 8
    /// 封面取色落地时的过渡。整页底色与 hero 渐变收口必须共用它，否则会错开露边。
    static let paletteTransition: Animation = .easeInOut(duration: 0.5)

    /// 整页底色由封面主色驱动（与首页 hero 呼应），文字层级仍用固定对比色。
    static func palette(for colorScheme: ColorScheme, cover: CoverColorPalette) -> RegularDetailPalette {
        ContentPalette.make(for: colorScheme, cover: cover)
    }
}

private typealias RegularDetailPalette = ContentPalette

/// 宽屏（macOS / iPad）资源详情页。
///
/// 窄屏见 `DetailView`。ViewModel 共用 `DetailViewModel`。
public struct RegularDetailView: View {
    @State private var model: DetailViewModel
    @State private var episodePage: Int = 0
    /// 长按角色立绘时临时放大；松手在 `onLongPressGesture(pressing:)` 里清空。
    @State private var heldCharacter: BangumiRelatedCharacter? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(RuleStoreCoordinator.self) private var ruleStore
    @Environment(FollowStore.self) private var followStore
    @Environment(BangumiAuthStore.self) private var auth
    @Environment(BangumiCollectionStore.self) private var collections
    var onTapPlay: (PlaybackRequest, SourceSearchCache?) -> Void
    var onTapTag: (String) -> Void

    public init(
        model: DetailViewModel,
        onTapPlay: @escaping (PlaybackRequest, SourceSearchCache?) -> Void,
        onTapTag: @escaping (String) -> Void
    ) {
        _model = State(initialValue: model)
        self.onTapPlay = onTapPlay
        self.onTapTag = onTapTag
    }

    /// 登录且条目是 bgm 上的真条目时，收藏与单集状态才有的谈。
    private var tracksBangumi: Bool {
        auth.isLoggedIn && model.item.id > 0
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        stretchyHero(viewportSize: proxy.size)
                        contentColumns(viewportWidth: proxy.size.width)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                if let heldCharacter {
                    characterImageMagnifier(heldCharacter, viewportSize: proxy.size)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .center))
                        )
                        .zIndex(20)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: heldCharacter?.id)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: heldCharacter?.id)
        }
        .ignoresSafeArea(edges: .top)
        .background {
            palette.background
                .ignoresSafeArea()
                .animation(RegularDetailStyle.paletteTransition, value: model.coverPalette)
        }
        .toolbarBackground(.hidden, for: .automatic)
        .task {
            // 详情页一露面就把嗅探那两笔固定开销预付掉，点播放时已经就绪。
            ExtractionWarmUp.prewarm()
            await model.load()
        }
        .task(id: ruleStore.installedRules.count) {
            await model.updateRules(ruleStore.enabledRules())
        }
        .task(id: BangumiEpisodeStateTrigger(subjectID: model.item.id, isLoggedIn: auth.isLoggedIn)) {
            guard tracksBangumi else { return }
            await collections.loadEpisodeStates(subjectID: model.item.id)
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

    private var palette: RegularDetailPalette {
        RegularDetailStyle.palette(for: colorScheme, cover: model.coverPalette)
    }

    // MARK: - Hero

    /// 下拉过滚时顶部锚定窗口、整体拉高 —— 与首页同一套，顶部不会因为弹性露出空隙。
    @ViewBuilder
    private func stretchyHero(viewportSize: CGSize) -> some View {
        let baseHeight = RegularDetailLayout.heroHeight(viewportHeight: viewportSize.height)
        GeometryReader { geo in
            let stretch = max(0, geo.frame(in: .global).minY)
            hero(width: viewportSize.width, height: baseHeight + stretch)
                .offset(y: -stretch)
        }
        .frame(height: baseHeight)
    }

    @ViewBuilder
    private func hero(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            heroBackdrop(width: width, height: height)

            HStack(alignment: .center, spacing: RegularDetailLayout.posterGap) {
                if RegularDetailLayout.showsPoster(width: width) {
                    poster(heroHeight: height)
                }
                heroCopy(heroHeight: height)
                    .frame(
                        width: RegularDetailLayout.heroTextWidth(width: width, heroHeight: height),
                        alignment: .leading
                    )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, RegularDetailLayout.horizontalPadding)
            .padding(.top, RegularDetailLayout.heroTopInset)
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// 背景 = 这张封面放大 + 模糊，再压暗、再叠一层同色环境光，最后收口到页面底色。
    @ViewBuilder
    private func heroBackdrop(width: CGFloat, height: CGFloat) -> some View {
        let cover = model.coverPalette
        let overscan = RegularDetailLayout.backdropOverscan
        ZStack {
            palette.background

            Color.clear
                .frame(width: width, height: height)
                .overlay {
                    RemoteImage(url: HomeHeroBannerLayout.coverURL(for: model.item)) {
                        cover.darkened.color
                    }
                    .frame(width: width * overscan, height: height * overscan)
                    .blur(radius: RegularDetailLayout.backdropBlurRadius, opaque: true)
                }
                .clipped()
                .overlay {
                    cover.darkened.color.opacity(RegularDetailLayout.backdropDim)
                }

            RadialGradient(
                colors: [
                    cover.color.opacity(RegularDetailLayout.glowOpacity),
                    cover.color.opacity(RegularDetailLayout.glowOpacity * 0.45),
                    .clear,
                ],
                center: RegularDetailLayout.glowCenter,
                startRadius: 0,
                endRadius: width * RegularDetailLayout.glowRadiusRatio
            )
            .blendMode(.plusLighter)

            // 顶部压暗，保证返回键 / 交通灯在亮画面上也读得出
            LinearGradient(
                colors: [.black.opacity(colorScheme == .dark ? 0.45 : 0.22), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .frame(maxHeight: .infinity, alignment: .top)

            // 底部收口到页面底色，和下方内容区无缝
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: palette.background.opacity(0.85), location: 0.86),
                    .init(color: palette.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(RegularDetailStyle.paletteTransition, value: model.coverPalette)
        .allowsHitTesting(false)
    }

    /// 海报按 3:4 原比例摆，套一圈细相框。
    @ViewBuilder
    private func poster(heroHeight: CGFloat) -> some View {
        let inset = RegularDetailLayout.posterFrameInset
        let shape = RoundedRectangle(
            cornerRadius: RegularDetailLayout.posterCornerRadius,
            style: .continuous
        )
        let frameShape = RoundedRectangle(
            cornerRadius: RegularDetailLayout.posterCornerRadius + inset,
            style: .continuous
        )
        Color.clear
            .frame(
                width: RegularDetailLayout.posterWidth(heroHeight: heroHeight),
                height: RegularDetailLayout.posterHeight(heroHeight: heroHeight)
            )
            .overlay {
                RemoteImage(url: HomeHeroBannerLayout.coverURL(for: model.item)) {
                    model.coverPalette.lifted.color
                }
            }
            .clipShape(shape)
            .padding(inset)
            .background(frameShape.fill(.black.opacity(0.22)))
            .overlay { frameShape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
            .accessibilityLabel(model.item.displayName)
    }

    @ViewBuilder
    private func heroCopy(heroHeight: CGFloat) -> some View {
        // 窗口矮下来时先丢可选信息（原名、简介），把间距也收紧。
        let compact = RegularDetailLayout.isCompactHero(heroHeight: heroHeight)
        VStack(alignment: .leading, spacing: 0) {
            if !model.metaTags.isEmpty {
                categoryChips
                    .padding(.bottom, compact ? 12 : 18)
            }

            Text(model.item.displayName)
                .font(.system(size: compact ? 34 : 46, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0), radius: 12, y: 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !compact, let latin = RegularHomeHeroLayout.latinTitle(for: model.item) {
                Text(latin)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            heroFactChips
                .padding(.top, compact ? 14 : 20)

            if !compact, !model.summary.isEmpty {
                summaryQuote
                    .padding(.top, 20)
            }

            heroActionBar
                .padding(.top, compact ? 16 : 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 官方分类标签（TV / 日本 / 漫画改）。
    @ViewBuilder
    private var categoryChips: some View {
        HStack(spacing: 8) {
            ForEach(model.metaTags.prefix(5), id: \.self) { tag in
                Text(tag)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.surface, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.hairline, lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 简介 —— 左侧一道竖线，读起来是「引文」而不是又一段正文。
    @ViewBuilder
    private var summaryQuote: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(palette.textPrimary.opacity(0.28))
                .frame(width: 2)
            Text(model.summary)
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private struct HeroFact {
        let symbol: String?
        let tint: Color
        let text: String
    }

    /// 评分 / 热度 / 年份 / 话数 / 片长 / Rank，做成一排规格块。
    @ViewBuilder
    private var heroFactChips: some View {
        let facts = heroFacts
        if !facts.isEmpty {
            WrapLayout(spacing: 10, lineSpacing: 10) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    HStack(spacing: 5) {
                        if let symbol = fact.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(fact.tint)
                        }
                        Text(fact.text)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: RegularDetailLayout.chipRadius, style: .continuous)
                            .fill(palette.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: RegularDetailLayout.chipRadius, style: .continuous)
                                    .strokeBorder(palette.hairline, lineWidth: 1)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroFacts: [HeroFact] {
        var facts: [HeroFact] = []
        if model.item.ratingScore > 0 {
            var text = String(format: "%.1f", model.item.ratingScore)
            if model.ratingTotal > 0 {
                text += " (\(DetailFormat.grouped(model.ratingTotal)))"
            }
            facts.append(HeroFact(symbol: "star.fill", tint: .yellow, text: text))
        }
        if model.heat > 0 {
            facts.append(
                HeroFact(
                    symbol: model.heatIsTrending ? "flame.fill" : "person.2.fill",
                    tint: .orange,
                    text: DetailFormat.heat(model.heat)
                )
            )
        }
        if let year = HomeHeroBannerLayout.yearString(from: model.airDate) {
            facts.append(HeroFact(symbol: "calendar", tint: palette.textTertiary, text: year))
        }
        if model.episodeCount > 0 {
            facts.append(
                HeroFact(symbol: "square.stack", tint: palette.textTertiary, text: "\(model.episodeCount) 话")
            )
        }
        if !model.episodeDuration.isEmpty {
            facts.append(
                HeroFact(symbol: "clock", tint: palette.textTertiary, text: model.episodeDuration)
            )
        }
        if model.item.rank > 0 {
            facts.append(
                HeroFact(symbol: "trophy", tint: palette.textTertiary, text: "Rank #\(model.item.rank)")
            )
        }
        return facts
    }

    @ViewBuilder
    private var heroActionBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                playButton
                if tracksBangumi {
                    collectionStatusButton
                } else {
                    followButton
                }
            }

            if let resumeDetailText {
                Text(resumeDetailText)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if tracksBangumi, let progress = bangumiProgressText {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            WrapLayout(spacing: 16, lineSpacing: 8) {
                statPill(title: "已选源", value: model.selectedSource?.ruleName ?? "暂无")
                statPill(title: "线路", value: selectedRoadLabel)
                statPill(title: "剧集", value: "\(model.currentEpisodes.count)")
            }
        }
    }

    @ViewBuilder
    private var playButton: some View {
        let request = model.playbackRequestForResume() ?? model.playbackRequestForFirstEpisode()
        Button {
            if let request {
                onTapPlay(request, model.sourceCache)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.playbackRequestForResume() == nil ? "play.fill" : "arrow.clockwise")
                Text(primaryActionTitle)
                    .fontWeight(.bold)
            }
            .foregroundStyle(TubeMonochrome.onFill(for: colorScheme))
            .frame(minWidth: 168, minHeight: 48)
            .padding(.horizontal, 18)
            .background(
                TubeMonochrome.fill(for: colorScheme),
                in: RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(request == nil)
        .opacity(request == nil ? 0.45 : 1)
    }

    @ViewBuilder
    private var followButton: some View {
        Button {
            try? followStore.toggle(model.item)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "star")
                        .opacity(isFollowed ? 0 : 1)
                        .scaleEffect(isFollowed ? 0.72 : 1)
                    Image(systemName: "star.fill")
                        .opacity(isFollowed ? 1 : 0)
                        .scaleEffect(isFollowed ? 1 : 0.72)
                }
                .foregroundStyle(isFollowed ? .yellow : palette.textPrimary)
                .frame(width: 18, height: 18)
                Text("追番")
                    .fontWeight(.semibold)
                    .foregroundStyle(isFollowed ? .yellow : palette.textPrimary)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 18)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.16), value: isFollowed)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statPill(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .font(.caption.weight(.bold))
    }

    private var selectedRoadLabel: String {
        guard let detail = model.selectedDetail,
            detail.roads.indices.contains(model.selectedRoadIndex)
        else {
            return "未选"
        }
        return detail.roads[model.selectedRoadIndex].label
    }

    private var primaryActionTitle: String {
        guard let historyHint = model.historyHint, model.playbackRequestForResume() != nil, historyHint.positionMs > 0 else {
            return "播放"
        }
        return "继续播放 \(formatMillis(historyHint.positionMs))"
    }

    private var resumeDetailText: String? {
        guard let historyHint = model.historyHint,
            model.playbackRequestForResume() != nil,
            historyHint.positionMs > 0
        else {
            return nil
        }
        return "\(historyHint.episodeTitle) \(formatMillis(historyHint.positionMs))"
    }

    private var isFollowed: Bool {
        followStore.contains(model.item)
    }

    /// 登录后的收藏状态按钮：和 `followButton` 同一副壳子，图标文案换成 bgm 状态。
    @ViewBuilder
    private var collectionStatusButton: some View {
        BangumiCollectionStatusMenu(item: model.item) { current in
            let tint = BangumiCollectionButtonStyle.tint(for: current, fallback: palette.textPrimary)
            HStack(spacing: 8) {
                Image(systemName: BangumiCollectionButtonStyle.systemImage(for: current))
                    .frame(width: 18, height: 18)
                Text(BangumiCollectionButtonStyle.title(for: current))
                    .fontWeight(.semibold)
            }
            .foregroundStyle(tint)
            .frame(minHeight: 48)
            .padding(.horizontal, 18)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var bangumiProgressText: String? {
        let subjectID = model.item.id
        let total = collections.episodeLists[subjectID]?.count ?? model.episodeCount
        return BangumiProgressLabel.text(
            watched: collections.watchedCount(subjectID: subjectID),
            total: total
        )
    }

    // MARK: - Content below hero

    @ViewBuilder
    private func contentColumns(viewportWidth: CGFloat) -> some View {
        let contentWidth = RegularDetailLayout.contentWidth(viewportWidth: viewportWidth)
        VStack(alignment: .leading, spacing: 0) {
            contentTabBar(width: contentWidth)
                .padding(.bottom, 28)
            tabContent(contentWidth: contentWidth)
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 96)
    }

    @ViewBuilder
    private func contentTabBar(width: CGFloat) -> some View {
        // 能放下就贴合内容；放不下则钉死在内容区宽度内，tabs 在容器里横滚。
        // 竖向 ScrollView 里若不限制，HStack ideal width 会把整页撑出屏宽。
        let maxWidth = max(0, width)
        ViewThatFits(in: .horizontal) {
            tabBarTrack(scrolling: false)
            tabBarTrack(scrolling: true)
                .frame(width: maxWidth, alignment: .leading)
                .clipShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func tabBarTrack(scrolling: Bool) -> some View {
        let tabs = HStack(spacing: 4) {
            ForEach(DetailTab.tabBarCases, id: \.self) { tab in
                tabBarItem(tab)
            }
        }
        .padding(5)

        Group {
            if scrolling {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabs
                }
            } else {
                tabs
            }
        }
        .background {
            Capsule(style: .continuous)
                .fill(palette.surface)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func tabBarItem(_ tab: DetailTab) -> some View {
        let selected = model.selectedTab == tab
        Button {
            Task { await model.selectTab(tab) }
        } label: {
            Text(tab.title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? palette.textPrimary : palette.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(selected ? palette.surfaceRaised : Color.clear)
                        .overlay {
                            if selected {
                                Capsule(style: .continuous)
                                    .strokeBorder(palette.hairline, lineWidth: 1)
                            }
                        }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    @ViewBuilder
    private func tabContent(contentWidth: CGFloat) -> some View {
        Group {
            if model.loadingCurrentTab {
                contentStatus(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "加载中",
                    message: "正在获取内容…"
                ) {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if let error = model.currentTabError {
                contentStatus(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "加载失败",
                    message: error
                )
            } else {
                switch model.selectedTab {
                case .overview, .comments:
                    // 吐槽已挪到概览底部，tab 栏不再有这一项
                    overviewContent(contentWidth: contentWidth)
                case .characters:
                    charactersContent
                case .reviews:
                    reviewsContent
                case .staff:
                    staffContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
    }

    // MARK: Overview

    /// 宽屏分两栏：左边是「要动的」（选集 / 简介 / 吐槽），右边是「查的」（资料 / 收藏 / 标签）。
    @ViewBuilder
    private func overviewContent(contentWidth: CGFloat) -> some View {
        if RegularDetailLayout.isTwoColumn(contentWidth: contentWidth) {
            HStack(alignment: .top, spacing: RegularDetailLayout.columnGap) {
                overviewMainColumn
                    .frame(width: RegularDetailLayout.mainColumnWidth(contentWidth: contentWidth), alignment: .leading)
                overviewSideColumn
                    .frame(width: RegularDetailLayout.sideColumnWidth, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 36) {
                overviewMainColumn
                overviewSideColumn
            }
        }
    }

    @ViewBuilder
    private var overviewMainColumn: some View {
        VStack(alignment: .leading, spacing: 36) {
            watchModule

            if !model.summary.isEmpty {
                contentModule(eyebrow: "ABOUT", title: "简介") {
                    ExpandableSummary(
                        text: model.summary,
                        collapsedLineLimit: 6,
                        textColor: palette.textSecondary,
                        accentColor: palette.textPrimary
                    )
                }
            }

            // 吐槽不再占一个 tab，常驻概览最下方
            contentModule(eyebrow: "COMMENTS", title: "吐槽") {
                overviewComments
            }
            .task { await model.loadCommentsIfNeeded() }
        }
    }

    /// 资料栏。整栏落在一块浅面板上，跟左边「要动的」那栏区分开。
    @ViewBuilder
    private var overviewSideColumn: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let collection = model.collection, collection.total > 0 {
                sideModule(title: "收藏") {
                    collectionStats(collection)
                }
            }

            if !model.factRows.isEmpty {
                sideModule(title: "资料") {
                    factList
                }
            }

            if !model.tags.isEmpty {
                sideModule(title: "标签") {
                    tagCloud
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: RegularDetailLayout.moduleRadius, style: .continuous)
                .fill(palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: RegularDetailLayout.moduleRadius, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var overviewComments: some View {
        if model.loadingTabs.contains(.comments) && model.comments.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在获取短评…")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            }
        } else if let error = model.tabErrors[.comments], model.comments.isEmpty {
            contentInlineHint(error)
        } else if model.comments.isEmpty {
            contentInlineHint("这部作品还没有短评。")
        } else {
            commentList
        }
    }

    /// 收藏分布：在看 / 想看 / 看过 / 搁置 / 抛弃。
    @ViewBuilder
    private func collectionStats(_ collection: BangumiCollection) -> some View {
        let entries: [(String, Int)] = [
            ("在看", collection.doing),
            ("想看", collection.wish),
            ("看过", collection.collect),
            ("搁置", collection.onHold),
            ("抛弃", collection.dropped),
        ].filter { $0.1 > 0 }

        WrapLayout(spacing: 22, lineSpacing: 14) {
            ForEach(entries, id: \.0) { label, count in
                VStack(alignment: .leading, spacing: 2) {
                    Text(DetailFormat.grouped(count))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    /// 资料表：左标签右值，靠细分隔线分行。
    @ViewBuilder
    private var factList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.factRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 14) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 68, alignment: .leading)
                    Text(row.1)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)

                if index < model.factRows.count - 1 {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var tagCloud: some View {
        WrapLayout(spacing: 6, lineSpacing: 6) {
            ForEach(model.tags.prefix(RegularDetailLayout.maxTagChips), id: \.name) { tag in
                Button {
                    onTapTag(tag.name)
                } label: {
                    Text(tag.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            Capsule(style: .continuous)
                                .fill(palette.surfaceRaised)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Watch

    @ViewBuilder
    private var watchModule: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WATCH")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text("选集播放")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 12)
                if !model.currentEpisodes.isEmpty {
                    Text("\(model.currentEpisodes.count) 集")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                sourceRail
                episodesContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sourceRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放源")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            if model.isSearchingSources && model.sources.isEmpty && model.blockedSources.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在匹配可播放源…")
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 4)
            } else if model.sources.isEmpty && model.blockedSources.isEmpty {
                Label(model.sourceSearchFailed ?? "暂无可播放源", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            } else {
                SourceRail(
                    groups: model.sourceGroups,
                    blockedSources: model.blockedSources,
                    selectedSourceID: model.selectedSource?.id,
                    layout: .wrap,
                    style: sourceRailStyle,
                    onSelect: { id in Task { await model.selectSource(id) } },
                    onUnblock: { model.openCaptcha(for: $0) }
                )

                if case .failed(let message) = model.selectedSourceState {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var sourceRailStyle: SourceRailStyle {
        SourceRailStyle(
            textPrimary: palette.textPrimary,
            textSecondary: palette.textSecondary,
            textTertiary: palette.textTertiary,
            selectedFill: palette.surfaceRaised,
            fill: .clear,
            hairline: palette.hairline
        )
    }

    @ViewBuilder
    private var episodesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("剧集")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            switch model.selectedSourceState {
            case .idle:
                contentInlineHint("请选择一个播放源")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在拉取剧集…")
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("剧集加载失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            case .loaded(let detail):
                episodeBrowser(detail: detail)
            }
        }
    }

    @ViewBuilder
    private func episodeBrowser(detail: AnimeDetail) -> some View {
        let episodes = model.currentEpisodes
        let pageSize = 100
        let totalPages = max(1, (episodes.count + pageSize - 1) / pageSize)
        let safePage = min(episodePage, totalPages - 1)
        let pageStart = safePage * pageSize
        let pageEnd = min(pageStart + pageSize, episodes.count)
        let resumeIndex = resumeEpisodeIndex

        VStack(alignment: .leading, spacing: 14) {
            if detail.roads.count > 1 {
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(detail.roads.indices, id: \.self) { index in
                        roadChip(label: detail.roads[index].label, index: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if totalPages > 1 {
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        pageChip(
                            page: page,
                            start: page * pageSize + 1,
                            end: min((page + 1) * pageSize, episodes.count),
                            isSelected: safePage == page
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if episodes.isEmpty {
                contentInlineHint("该线路暂无剧集")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: RegularDetailLayout.episodeMin, maximum: 140),
                            spacing: 10
                        )
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(episodes[pageStart..<pageEnd].enumerated()), id: \.element.id) { pageIndex, episode in
                        let absoluteIndex = pageStart + pageIndex
                        Button {
                            if let request = model.playbackRequest(episodeIndex: absoluteIndex) {
                                onTapPlay(request, model.sourceCache)
                            }
                        } label: {
                            episodeCell(
                                episode: episode,
                                index: absoluteIndex,
                                isResume: resumeIndex == absoluteIndex
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onChange(of: model.selectedRoadIndex) { _, _ in episodePage = 0 }
        .onChange(of: model.selectedSourceID) { _, _ in episodePage = 0 }
    }

    @ViewBuilder
    private func roadChip(label: String, index: Int) -> some View {
        let isSelected = model.selectedRoadIndex == index
        Button {
            model.selectRoad(index)
            episodePage = 0
        } label: {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? palette.surfaceRaised : Color.clear)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.hairline.opacity(isSelected ? 1 : 0.5), lineWidth: 1)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pageChip(page: Int, start: Int, end: Int, isSelected: Bool) -> some View {
        Button {
            episodePage = page
        } label: {
            Text("\(start)–\(end)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? palette.surfaceRaised : Color.clear)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func episodeCell(episode: Episode, index: Int, isResume: Bool) -> some View {
        VStack(spacing: 6) {
            Text(episodeNumberLabel(for: episode, fallbackIndex: index))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(isResume ? TubeMonochrome.fill(for: colorScheme) : palette.textTertiary)
                .tracking(0.4)
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background {
            RoundedRectangle(cornerRadius: RegularDetailLayout.chipRadius, style: .continuous)
                .fill(
                    isResume
                        ? TubeMonochrome.fill(for: colorScheme).opacity(0.12)
                        : palette.surfaceRaised
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: RegularDetailLayout.chipRadius, style: .continuous)
                .strokeBorder(
                    isResume
                        ? TubeMonochrome.fill(for: colorScheme).opacity(0.55)
                        : palette.hairline,
                    lineWidth: 1
                )
        }
        .overlay(alignment: .topTrailing) {
            if tracksBangumi, collections.isEpisodeWatched(subjectID: model.item.id, episodeIndex: index) {
                BangumiEpisodeWatchedBadge()
            }
        }
        .contextMenu {
            if tracksBangumi {
                let watched = collections.isEpisodeWatched(subjectID: model.item.id, episodeIndex: index)
                Button {
                    Task {
                        await collections.toggleEpisodeWatched(
                            subjectID: model.item.id,
                            episodeIndex: index,
                            item: model.item
                        )
                    }
                } label: {
                    Label(watched ? "标为未看" : "标为看过", systemImage: watched ? "circle" : "checkmark.circle")
                }
            }
        }
    }

    private func episodeNumberLabel(for episode: Episode, fallbackIndex: Int) -> String {
        let number = episode.index >= 0 ? episode.index + 1 : fallbackIndex + 1
        return String(format: "EP %02d", number)
    }

    private var resumeEpisodeIndex: Int? {
        guard let hint = model.historyHint,
            model.selectedSource?.ruleName == hint.ruleName,
            model.currentEpisodes.indices.contains(hint.episodeIndex),
            model.currentEpisodes[hint.episodeIndex].title == hint.episodeTitle
        else {
            return nil
        }
        return hint.episodeIndex
    }

    // MARK: Social tabs

    @ViewBuilder
    private var commentList: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.comments) { comment in
                flatRow {
                    HStack(alignment: .top, spacing: 14) {
                        circularAvatar(url: comment.avatarURL, title: comment.authorName, size: 40)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(comment.authorName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 8)
                                Text(comment.publishedAt)
                                    .font(.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            if !comment.stateLabel.isEmpty || !comment.ratingLabel.isEmpty {
                                HStack(spacing: 8) {
                                    if !comment.stateLabel.isEmpty {
                                        Text(comment.stateLabel)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(palette.surfaceRaised, in: Capsule(style: .continuous))
                                    }
                                    if !comment.ratingLabel.isEmpty {
                                        Text(comment.ratingLabel.replacingOccurrences(of: "stars", with: "★"))
                                    }
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.textTertiary)
                            }
                            Text(comment.body)
                                .font(.body)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var characterGridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: RegularDetailLayout.characterMin,
                    maximum: RegularDetailLayout.characterMax
                ),
                spacing: RegularDetailLayout.characterSpacing,
                alignment: .top
            ),
        ]
    }

    @ViewBuilder
    private var charactersContent: some View {
        if model.characters.isEmpty {
            contentStatus(
                systemImage: "person.3",
                title: "暂无角色",
                message: "还没有角色资料。"
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.characters.count) 位角色")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textTertiary)

                LazyVGrid(
                    columns: characterGridColumns,
                    alignment: .leading,
                    spacing: RegularDetailLayout.characterSpacing
                ) {
                    ForEach(model.characters) { character in
                        characterCard(character)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func characterCard(_ character: BangumiRelatedCharacter) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            // 完整装入卡片：fit 居中不裁切；立绘多为白底，容器用纯白避免两侧色条。
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(RegularDetailLayout.characterImageAspect, contentMode: .fit)
                .background(Color.white)
                .overlay {
                    characterPortrait(
                        url: URL(string: character.images.best),
                        title: character.name,
                        contentMode: .fit
                    )
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(palette.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                // 只挂在立绘上，避免整张卡（含文字区）抢走 ScrollView 滚动。
                .onLongPressGesture(
                    minimumDuration: 0.4,
                    maximumDistance: 10,
                    pressing: { isPressing in
                        if !isPressing {
                            heldCharacter = nil
                        }
                    },
                    perform: {
                        heldCharacter = character
                    }
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(character.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if !character.relation.isEmpty {
                    Text(character.relation)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                if let actor = character.actors.first {
                    Text("CV \(actor.name)")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 角色立绘。卡片用 `.fit` 保证人物完整；放大预览同样 fit，只是画布更大。
    @ViewBuilder
    private func characterPortrait(
        url: URL?,
        title: String,
        contentMode: ContentMode
    ) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                ZStack {
                    Color.white
                    Text(String(title.prefix(1)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
            }
        }
    }

    @ViewBuilder
    private func characterImageMagnifier(
        _ character: BangumiRelatedCharacter,
        viewportSize: CGSize
    ) -> some View {
        let maxImageWidth = min(viewportSize.width - 48, 420)
        let maxImageHeight = min(viewportSize.height * 0.72, 560)
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.62 : 0.48)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                // 与列表卡一致：先铺满纯白容器，再 fit 居中立绘，避免透明区透出暗色。
                Color.white
                    .frame(width: maxImageWidth, height: maxImageHeight)
                    .overlay {
                        characterPortrait(
                            url: URL(string: character.images.best),
                            title: character.name,
                            contentMode: .fit
                        )
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(palette.hairline, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 28, y: 14)

                VStack(spacing: 4) {
                    Text(character.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    if !character.relation.isEmpty {
                        Text(character.relation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    if let actor = character.actors.first {
                        Text("CV \(actor.name)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var reviewsContent: some View {
        if model.reviews.isEmpty {
            contentStatus(
                systemImage: "doc.text",
                title: "暂无评论",
                message: "还没有长评。"
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.reviews) { review in
                    flatRow {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                circularAvatar(url: review.avatarURL, title: review.authorName, size: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(review.authorName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    HStack(spacing: 8) {
                                        if !review.publishedAt.isEmpty {
                                            Text(review.publishedAt)
                                        }
                                        if !review.replyCount.isEmpty {
                                            Text(review.replyCount)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(palette.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }

                            Text(review.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !review.summary.isEmpty {
                                Text(review.summary)
                                    .font(.body)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(5)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var staffContent: some View {
        if model.staff.isEmpty {
            contentStatus(
                systemImage: "person.crop.rectangle.stack",
                title: "暂无制作人员",
                message: "还没有 staff 资料。"
            )
        } else {
            // 宽屏一行塞得下两个人，单列会拉出一条又长又空的清单。
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: 24, alignment: .top)],
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(model.staff) { person in
                    flatRow {
                        staffRow(person)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func staffRow(_ person: BangumiRelatedPerson) -> some View {
        HStack(spacing: 14) {
            squareAvatar(url: URL(string: person.images.best), title: person.name, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if !person.career.isEmpty {
                    Text(person.career.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                if !person.eps.isEmpty {
                    Text(person.eps)
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if !person.relation.isEmpty {
                Text(person.relation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.surfaceRaised, in: Capsule(style: .continuous))
            }
        }
    }

    // MARK: Content chrome

    /// 分区标题 + 内容直接落在背景上（无卡片、无描边），与首页分区一致。
    @ViewBuilder
    private func contentModule<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 资料栏里的小分区：面板已经把它们框在一起了，标题降一档就够。
    @ViewBuilder
    private func sideModule<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 列表行：无卡片，靠细分隔线断行。
    @ViewBuilder
    private func flatRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func contentStatus<Accessory: View>(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func contentInlineHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(palette.textTertiary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func circularAvatar(url: URL?, title: String, size: CGFloat) -> some View {
        avatar(url: url, title: title)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func squareAvatar(url: URL?, title: String, size: CGFloat) -> some View {
        avatar(url: url, title: title)
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func avatar(url: URL?, title: String) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    palette.surfaceRaised
                    Text(String(title.prefix(1)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .clipped()
    }

    private func formatMillis(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ExpandableSummary: View {
    let text: String
    let collapsedLineLimit: Int
    let textColor: Color
    let accentColor: Color

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(6)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(measurementOverlay)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开全部")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measurementOverlay: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.body)
                .lineSpacing(6)
                .lineLimit(collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { collapsed in
                    Text(text)
                        .font(.body)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { full in
                            Color.clear.onAppear {
                                isTruncated = full.size.height > collapsed.size.height + 0.5
                            }
                            .onChange(of: full.size.height) { _, newHeight in
                                isTruncated = newHeight > collapsed.size.height + 0.5
                            }
                        })
                        .hidden()
                })
        }
        .hidden()
        .accessibilityHidden(true)
    }
}
