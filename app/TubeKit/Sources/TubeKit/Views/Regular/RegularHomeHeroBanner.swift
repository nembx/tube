import SwiftUI

/// 宽屏 Hero 的布局参数。
///
/// 设计要点，以及它为什么长这样：
///
/// Bangumi 给的是竖版海报（短边约 1000px），宽屏里**只要把它拉大就一定糊**。
/// 所以整个 Hero 反过来做 —— 画面里唯一出现封面像素的地方是左侧那张按 3:4
/// 原比例、尺寸压在源图像素以内的海报，其余全是纯色：一层跟着封面主色走的
/// 环境光把整幅铺满，右侧是排版信息。低分辨率因此完全不进画面。
enum RegularHomeHeroLayout {
    /// Hero 吃掉整个视口，只在底部留一条"下面还有东西"的提示高度。
    static let bottomPeek: CGFloat = 132
    /// 高度下限 = 精简版内容排下来需要的高度（含顶栏让位）。
    /// 窗口比这还矮时 hero 就溢出视口、靠滚动看 —— 也绝不能让内容缩到顶栏底下去。
    static let minHeight: CGFloat = 540
    static let maxHeight: CGFloat = 1000
    /// 低于这个高度走精简版：收起原名和简介，缩略图和标题也降一档。
    static let compactThreshold: CGFloat = 640
    static let horizontalPadding: CGFloat = 56
    /// 海报与右侧信息栏之间的间距。两者是紧挨着的一组。
    static let posterGap: CGFloat = 44
    /// 右侧信息栏最大宽度 —— 再宽就拉成没法读的长句。
    static let metaMaxWidth: CGFloat = 620
    static let titleLineLimit: Int = 2
    static let summaryLineLimit: Int = 2

    /// 海报按封面原比例（3:4）摆放，不做任何拉伸。
    static let posterAspectRatio: CGFloat = 3.0 / 4.0
    static let posterHeightRatio: CGFloat = 0.60
    static let posterMinHeight: CGFloat = 300
    /// 上限压在 480：源图短边约 1000px，@2x 下 480pt = 960px，还在原图以内。
    static let posterMaxHeight: CGFloat = 480
    static let posterCornerRadius: CGFloat = 12
    /// 海报外那圈相框：边框与画面之间留这么宽。窄一点，别把海报框成相片。
    static let posterFrameInset: CGFloat = 6
    /// 窗口窄到这个宽度以下就不摆海报，把宽度全留给信息栏。
    static let posterMinimumWindowWidth: CGFloat = 900

    /// 快速点播条里的缩略图。
    static let switchThumbHeight: CGFloat = 92
    static let compactSwitchThumbHeight: CGFloat = 68
    static let switchThumbSpacing: CGFloat = 10
    static let switchThumbCornerRadius: CGFloat = 8
    /// 选中环。画在缩略图内侧，所以不会被 hero 的裁剪切掉。
    static let switchThumbRingWidth: CGFloat = 3

    /// 背景是**这张封面本身**放大后模糊出来的，不是一块凭空的渐变色。
    ///
    /// 半径的取法是个取舍：小了会露出低分辨率的马赛克，大了就糊成纯色块、
    /// 看不出跟封面还有关系。28 这一档刚好把像素抹掉、把构图和色块分布留下。
    static let backdropBlurRadius: CGFloat = 28
    /// 模糊会把边缘吸淡，背景要超铺一圈盖住。
    static let backdropOverscan: CGFloat = 1.3
    /// 模糊底上再压暗，保证白字可读。
    static let backdropDim: Double = 0.42

    /// 环境光：叠在模糊底之上，把整幅色调收拢到封面主色。只作统一，不当主角。
    static let glowCenter = UnitPoint(x: 0.28, y: 0.42)
    static let glowRadiusRatio: CGFloat = 0.9
    static let glowOpacity: Double = 0.26
    /// 右上角再补一小团反光，避免整幅只有一个光心显得平。
    static let counterGlowCenter = UnitPoint(x: 0.86, y: 0.12)
    static let counterGlowRadiusRatio: CGFloat = 0.45
    static let counterGlowOpacity: Double = 0.1

    /// 自动轮播间隔。
    static let autoAdvanceInterval: Duration = .seconds(6)
    static let crossfadeDuration: Double = 0.55

    /// 全幅：视口高减去底部露出的那一条。
    static func contentHeight(viewportHeight: CGFloat) -> CGFloat {
        min(maxHeight, max(minHeight, viewportHeight - bottomPeek))
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

    /// 矮窗口下收起原名和简介 —— 挤不下的时候，先丢可选信息，不能让内容溢出。
    static func isCompact(heroHeight: CGFloat) -> Bool {
        heroHeight < compactThreshold
    }

    static func switchThumbHeight(heroHeight: CGFloat) -> CGFloat {
        isCompact(heroHeight: heroHeight) ? compactSwitchThumbHeight : switchThumbHeight
    }

    static func switchThumbWidth(heroHeight: CGFloat) -> CGFloat {
        switchThumbHeight(heroHeight: heroHeight) * posterAspectRatio
    }

    static func titleSize(heroHeight: CGFloat) -> CGFloat {
        isCompact(heroHeight: heroHeight) ? 34 : 46
    }

    /// 信息栏可用宽度：先给海报连相框留够，剩下的再夹到可读上限。
    static func textWidth(width: CGFloat, heroHeight: CGFloat) -> CGFloat {
        let bare = max(240, width - horizontalPadding * 2)
        guard showsPoster(width: width) else {
            return min(metaMaxWidth, bare)
        }
        let available = bare
            - posterWidth(heroHeight: heroHeight)
            - posterFrameInset * 2
            - posterGap
        return min(metaMaxWidth, max(240, available))
    }

    /// 下一页；到尾回环。空列表 / 单页时原地不动。
    static func nextIndex(current: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let normalized = min(max(0, current), count - 1)
        return (normalized + 1) % count
    }

    /// 从 trending 的 info 串里捞话数，形如 `14话 / 2026年7月4日 / 导演`。
    /// 捞不到就返回 nil —— 宁可不显示，也不编一个数字出来。
    static func episodeCountText(fromInfo info: String) -> String? {
        guard let range = info.range(of: #"\d+(?=话)"#, options: .regularExpression) else {
            return nil
        }
        return "\(info[range]) 集"
    }

    /// 原名（拉丁 / 日文），和中文标题相同时不重复显示。
    static func latinTitle(for item: BangumiItem) -> String? {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.displayName else { return nil }
        return name
    }
}

/// 宽屏（macOS / iPad）首页 Hero。
///
/// 不给手动拖动切换：定时自动轮播 + 交叉淡入，底部一条 TOP 5 快速点播可直接跳。
/// 静止时整块零重绘。
///
/// 层叠（由底到顶）：
/// 1. 影院黑 + 跟着封面主色走的环境光
/// 2. 左侧：带相框和角标的原比例海报（画面里唯一的封面像素）
/// 3. 右侧：类型 chips / 标题 / 原名 / 引文 / 事实 chips / 行动按钮 / 快速点播条
struct RegularHomeHeroBanner: View {
    let items: [BangumiItem]
    let activeIndex: Int
    let palettes: [Int: CoverColorPalette]
    var viewportHeight: CGFloat
    var onChangeIndex: (Int) -> Void
    var onTapItem: (BangumiItem) -> Void

    @State private var currentIndex: Int = 0
    @Environment(\.regularTopBarPlacement) private var topBarPlacement
    @Environment(\.regularShellPageIsActive) private var isActive

    private var totalHeight: CGFloat {
        RegularHomeHeroLayout.contentHeight(viewportHeight: viewportHeight)
    }

    private var safeIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(0, currentIndex), items.count - 1)
    }

    private var currentItem: BangumiItem? {
        items.indices.contains(safeIndex) ? items[safeIndex] : nil
    }

    private func palette(for item: BangumiItem) -> CoverColorPalette {
        palettes[item.id] ?? .fallback
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                ZStack {
                    RegularShellLayout.cinemaBackground

                    if let currentItem {
                        // 背景跟着当前这条走，所以整块（底 + 内容）一起交叉淡入
                        ZStack {
                            ambientGlow(item: currentItem, width: width)
                            content(currentItem, width: width)
                        }
                        .id(currentItem.id)
                        // 必须先压成一层再淡入淡出：不然透明度会逐层作用到子视图上，
                        // 底部那条收口到影院黑的渐变自己变半透明、盖不住加亮过的环境光，
                        // 切换途中 hero 底边就停在偏棕色，和下方页面之间露出一条硬边。
                        .compositingGroup()
                        .transition(.opacity)
                    }
                }
                .frame(width: width, height: totalHeight)
                .clipped()
                .animation(
                    .easeInOut(duration: RegularHomeHeroLayout.crossfadeDuration),
                    value: safeIndex
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight)
            .onAppear {
                currentIndex = min(max(0, activeIndex), items.count - 1)
            }
            // 自动轮播：`.task(id:)` 在换页时自动取消重来，等于每页各计一次时。
            // 首页被切走后仍留在视图树里，这时 id 变成 -1 把等待中的那次取消掉 ——
            // 看不见的页不该每隔几秒就把整块 hero 重绘一遍。
            .task(id: isActive ? safeIndex : -1) {
                guard isActive, items.count > 1 else { return }
                try? await Task.sleep(for: RegularHomeHeroLayout.autoAdvanceInterval)
                guard !Task.isCancelled else { return }
                select(RegularHomeHeroLayout.nextIndex(current: safeIndex, count: items.count))
            }
        }
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        onChangeIndex(index)
    }

    // MARK: - 环境光

    /// 背景 = 这张封面放大 + 模糊，再压暗、再叠一层同色环境光收拢色调。
    ///
    /// 模糊到看不出像素、但看得出是它 —— 低分辨率被抹掉了，封面和画面的关系还在。
    @ViewBuilder
    private func ambientGlow(item: BangumiItem, width: CGFloat) -> some View {
        let palette = palette(for: item)
        let overscan = RegularHomeHeroLayout.backdropOverscan
        ZStack {
            RegularShellLayout.cinemaBackground

            Color.clear
                .frame(width: width, height: totalHeight)
                .overlay {
                    RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
                        palette.darkened.color
                    }
                    .frame(width: width * overscan, height: totalHeight * overscan)
                    .blur(radius: RegularHomeHeroLayout.backdropBlurRadius, opaque: true)
                }
                .clipped()
                .overlay {
                    palette.darkened.color.opacity(RegularHomeHeroLayout.backdropDim)
                }

            RadialGradient(
                colors: [
                    palette.color.opacity(RegularHomeHeroLayout.glowOpacity),
                    palette.color.opacity(RegularHomeHeroLayout.glowOpacity * 0.45),
                    .clear,
                ],
                center: RegularHomeHeroLayout.glowCenter,
                startRadius: 0,
                endRadius: width * RegularHomeHeroLayout.glowRadiusRatio
            )
            .blendMode(.plusLighter)

            RadialGradient(
                colors: [
                    palette.lifted.color.opacity(RegularHomeHeroLayout.counterGlowOpacity),
                    .clear,
                ],
                center: RegularHomeHeroLayout.counterGlowCenter,
                startRadius: 0,
                endRadius: width * RegularHomeHeroLayout.counterGlowRadiusRatio
            )
            .blendMode(.plusLighter)

            // 底部收口到影院黑，和下方分区流无缝
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: RegularShellLayout.cinemaBackground.opacity(0.8), location: 0.85),
                    .init(color: RegularShellLayout.cinemaBackground, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ item: BangumiItem, width: CGFloat) -> some View {
        // 顶部让开悬浮顶栏，剩下的空间里整组垂直居中。
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: RegularHomeHeroLayout.posterGap) {
                if RegularHomeHeroLayout.showsPoster(width: width) {
                    poster(for: item)
                }

                infoColumn(item)
                    .frame(
                        width: RegularHomeHeroLayout.textWidth(
                            width: width, heroHeight: totalHeight
                        ),
                        alignment: .leading
                    )

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, RegularHomeHeroLayout.horizontalPadding)
        .padding(.top, RegularShellLayout.contentTopInset(for: topBarPlacement))
        .frame(width: width, height: totalHeight, alignment: .leading)
    }

    // MARK: - 海报

    /// 海报按 3:4 原比例摆，套一圈细相框，四角压角标。
    @ViewBuilder
    private func poster(for item: BangumiItem) -> some View {
        let inset = RegularHomeHeroLayout.posterFrameInset
        let shape = RoundedRectangle(
            cornerRadius: RegularHomeHeroLayout.posterCornerRadius,
            style: .continuous
        )
        let frameShape = RoundedRectangle(
            cornerRadius: RegularHomeHeroLayout.posterCornerRadius + inset,
            style: .continuous
        )
        Button {
            onTapItem(item)
        } label: {
            Color.clear
                .frame(
                    width: RegularHomeHeroLayout.posterWidth(heroHeight: totalHeight),
                    height: RegularHomeHeroLayout.posterHeight(heroHeight: totalHeight)
                )
                .overlay {
                    RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
                        palette(for: item).lifted.color
                    }
                }
                .overlay { posterCorners(for: item) }
                .clipShape(shape)
                .padding(inset)
                .background(frameShape.fill(.black.opacity(0.22)))
                .overlay { frameShape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
                .contentShape(frameShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName)
    }

    /// 四角角标：左上 TOP n + 年份，右上 评分，左下 话数。
    @ViewBuilder
    private func posterCorners(for item: BangumiItem) -> some View {
        let year = HomeHeroBannerLayout.yearString(from: item.airDate)
            ?? HomeHeroBannerLayout.yearString(fromInfo: item.info)
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    badge("TOP \(safeIndex + 1)", tint: .red)
                    if let year {
                        badge(year, tint: nil)
                    }
                    Spacer(minLength: 0)
                    if item.ratingScore > 0 {
                        badge(
                            String(format: "%.1f", item.ratingScore),
                            tint: nil,
                            symbol: "star.fill"
                        )
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    if let episodes = RegularHomeHeroLayout.episodeCountText(fromInfo: item.info) {
                        Text(episodes)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func badge(_ text: String, tint: Color?, symbol: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint ?? .black.opacity(0.55))
        }
    }

    // MARK: - 信息栏

    @ViewBuilder
    private func infoColumn(_ item: BangumiItem) -> some View {
        // 窗口矮下来时先丢可选信息（原名、简介），把间距也收紧 ——
        // 挤不下的时候宁可少说两句，也不能让整栏顶到悬浮顶栏底下去。
        let compact = RegularHomeHeroLayout.isCompact(heroHeight: totalHeight)
        VStack(alignment: .leading, spacing: 0) {
            genreRow(for: item)
                .padding(.bottom, compact ? 12 : 18)

            Text(item.displayName)
                .font(.system(
                    size: RegularHomeHeroLayout.titleSize(heroHeight: totalHeight),
                    weight: .heavy,
                    design: .rounded
                ))
                .foregroundStyle(.white)
                .lineLimit(RegularHomeHeroLayout.titleLineLimit)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !compact, let latin = RegularHomeHeroLayout.latinTitle(for: item) {
                Text(latin.uppercased())
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !compact {
                summaryQuote(for: item)
                    .padding(.top, 22)
            }

            factChips(for: item)
                .padding(.top, compact ? 14 : 22)

            actionRow(for: item)
                .padding(.top, compact ? 16 : 26)

            quickSwitch
                .padding(.top, compact ? 18 : 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 类型 chips。
    @ViewBuilder
    private func genreRow(for item: BangumiItem) -> some View {
        let genres = (item.metaTags.isEmpty ? item.tags.map(\.name) : item.metaTags).prefix(4)
        if !genres.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(genres), id: \.self) { genre in
                    Text(genre)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 简介 —— 左侧一道竖线，读起来是"引文"而不是又一段正文。
    @ViewBuilder
    private func summaryQuote(for item: BangumiItem) -> some View {
        let detail = HomeHeroBannerLayout.detailText(for: item)
        // trending 不返回 summary，回落到 info 那串制作人员 —— 那不是"引文"，别装成引文。
        let isSummary = !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !detail.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 2)
                Text(detail)
                    .font(.callout)
                    .italic(isSummary)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(RegularHomeHeroLayout.summaryLineLimit)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 评分 / 热度 / 话数，做成一排规格块。
    @ViewBuilder
    private func factChips(for item: BangumiItem) -> some View {
        let facts = factItems(for: item)
        if !facts.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 {
                        Text("·").foregroundStyle(.white.opacity(0.3))
                    }
                    HStack(spacing: 5) {
                        if let symbol = fact.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(fact.tint)
                        }
                        Text(fact.text)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct HeroFact {
        let symbol: String?
        let tint: Color
        let text: String
    }

    private func factItems(for item: BangumiItem) -> [HeroFact] {
        var facts: [HeroFact] = []
        if item.ratingScore > 0 {
            facts.append(HeroFact(
                symbol: "star.fill",
                tint: .yellow,
                text: String(format: "%.1f", item.ratingScore)
            ))
        }
        if item.heat > 0 {
            facts.append(HeroFact(
                symbol: "flame.fill",
                tint: .orange,
                text: HomeHeroBannerLayout.heatText(item.heat)
            ))
        }
        if let episodes = RegularHomeHeroLayout.episodeCountText(fromInfo: item.info) {
            facts.append(HeroFact(symbol: nil, tint: .white, text: episodes))
        }
        return facts
    }

    /// 主行动按钮 + 一条纯事实的补充（开播日期）。
    @ViewBuilder
    private func actionRow(for item: BangumiItem) -> some View {
        HStack(spacing: 14) {
            GlassPrimaryButton("立即观看", systemImage: "play.fill") {
                onTapItem(item)
            }

            let air = item.airDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !air.isEmpty {
                Text("开播 \(air)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.06))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                            }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 快速点播

    /// 轮播照常自动走；这条只是让你想看哪张就直接跳过去，不用等。
    @ViewBuilder
    private var quickSwitch: some View {
        if items.count > 1 {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)

                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("TOP \(items.count) 热门番组快速点播")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: RegularHomeHeroLayout.switchThumbSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switchThumb(item, index: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func switchThumb(_ item: BangumiItem, index: Int) -> some View {
        let isCurrent = index == safeIndex
        let shape = RoundedRectangle(
            cornerRadius: RegularHomeHeroLayout.switchThumbCornerRadius,
            style: .continuous
        )
        Button {
            select(index)
        } label: {
            Color.clear
                .frame(
                    width: RegularHomeHeroLayout.switchThumbWidth(heroHeight: totalHeight),
                    height: RegularHomeHeroLayout.switchThumbHeight(heroHeight: totalHeight)
                )
                .overlay {
                    RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
                        palette(for: item).lifted.color
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .overlay(alignment: .topLeading) {
                    Text("#\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                }
                .clipShape(shape)
                .opacity(isCurrent ? 1 : 0.55)
                // 环画在缩略图**内侧**：画在外面时，第一张的左边那道会被 hero 的裁剪切掉。
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(isCurrent ? 1 : 0),
                        lineWidth: RegularHomeHeroLayout.switchThumbRingWidth
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.25), value: isCurrent)
        .accessibilityLabel("第 \(index + 1) 条：\(item.displayName)")
    }
}
