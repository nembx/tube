import SwiftUI

enum HomeHeroBannerLayout {
    /// Banner 总高占视口高度比例（含状态栏区域）。
    static let viewportHeightRatio: CGFloat = 0.56
    /// 封面图占 banner 总高的比例，剩余部分是实心底色区。
    static let imageHeightRatio: CGFloat = 0.8
    /// 极小窗口兜底。
    static let minHeight: CGFloat = 360
    static let horizontalPadding: CGFloat = 20
    static let titleLineLimit: Int = 2
    static let summaryLineLimit: Int = 4
    static let maxTags: Int = 3
    static let pageBarHeight: CGFloat = 4
    static let pageBarWidth: CGFloat = 12
    static let pageBarActiveWidth: CGFloat = 24
    static let pageBarSpacing: CGFloat = 6
    /// 渐变从图片高度的这个比例开始出现，图片底边处完全实心。
    static let scrimStart: CGFloat = 0.42
    /// 封面图相对页面的视差速度差：0 = 图完全不动，1 = 与页面同速（即无视差）。
    static let parallaxFactor: CGFloat = 0.18
    /// 指示器被提到轮播外层后固定不动，页内文案要给它让出这段高度。
    static let pageBarReservedHeight: CGFloat = 16

    /// 封面图必须比页宽更宽，否则反向位移时会露出空边。
    static func imageOverscanWidth(pageWidth: CGFloat) -> CGFloat {
        max(0, pageWidth) * (1 + 2 * parallaxFactor)
    }

    /// 页面偏离屏幕的比例（0 = 正在屏幕上，±1 = 左右各一页）→ 封面图在页内的反向位移。
    static func parallaxOffset(progress: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        let clamped = min(1, max(-1, progress))
        return -clamped * pageWidth * parallaxFactor
    }

    /// 当前占屏最多的那一页 —— 跨过半页即换人，全局底色跟它走。
    static func dominantIndex(scrollOffset: CGFloat, pageWidth: CGFloat, pageCount: Int) -> Int {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let raw = Int((scrollOffset / pageWidth).rounded())
        return min(max(0, raw), pageCount - 1)
    }

    // MARK: - 无限循环
    //
    // `.paging` 没有原生循环，靠铺三倍数组伪造：[本体, 本体, 本体]，开局停中段。
    // 吸页停稳后若落到首段或尾段，把 scrollPosition 静默搬回中段的同名槽位 ——
    // 三段内容完全一致，所以搬迁在画面上不可见。

    /// 循环需要铺的总槽位数；单页无需循环。
    static func loopedSlotCount(itemCount: Int) -> Int {
        itemCount <= 1 ? max(0, itemCount) : itemCount * 3
    }

    /// 开局落点：中段里 activeIndex 对应的槽位。
    static func loopStartSlot(itemCount: Int, activeIndex: Int) -> Int {
        guard itemCount > 1 else { return 0 }
        return itemCount + min(max(0, activeIndex), itemCount - 1)
    }

    /// 槽位 → 真实条目下标。
    static func realIndex(slot: Int, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let wrapped = slot % itemCount
        return wrapped < 0 ? wrapped + itemCount : wrapped
    }

    /// 需要静默搬迁时返回目标槽位；已在中段则返回 `nil`。
    static func recenteredSlot(slot: Int, itemCount: Int) -> Int? {
        guard itemCount > 1 else { return nil }
        let target = itemCount + realIndex(slot: slot, itemCount: itemCount)
        return target == slot ? nil : target
    }

    /// 指示器高亮权重：位置与下标的环形距离，跨首尾时高亮绕回而不是横穿整排。
    static func pageBarWeight(position: CGFloat, index: Int, itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let count = CGFloat(itemCount)
        var wrapped = position.truncatingRemainder(dividingBy: count)
        if wrapped < 0 { wrapped += count }
        let raw = abs(wrapped - CGFloat(index))
        return max(0, 1 - min(raw, count - raw))
    }

    /// Banner 封面图地址：优先大图，缺失时回落到列表图。
    static func coverURL(for item: BangumiItem) -> URL? {
        let raw = item.images.best.isEmpty ? item.images.listBest : item.images.best
        return URL(string: raw)
    }

    static func contentHeight(viewportHeight: CGFloat) -> CGFloat {
        max(minHeight, viewportHeight * viewportHeightRatio)
    }

    static func imageHeight(totalHeight: CGFloat) -> CGFloat {
        totalHeight * imageHeightRatio
    }

    /// List 行高度 = 视口比例高（topInset 只做文案避让）。
    static func totalHeight(viewportHeight: CGFloat, topInset: CGFloat = 0) -> CGFloat {
        _ = topInset
        return contentHeight(viewportHeight: viewportHeight)
    }

    /// 热度数字：上千折成 `9.9k`，避免挤掉后面的标签。
    static func heatText(_ heat: Int) -> String {
        guard heat >= 1000 else { return String(heat) }
        let thousands = Double(heat) / 1000
        return String(format: "%.1fk", thousands)
    }

    /// 评分 / 热度之后的事实项：年份 + 官方分类标签（metaTags 缺失时回落到用户标签）。
    static func factTexts(for item: BangumiItem) -> [String] {
        var texts: [String] = []
        if let year = yearString(from: item.airDate) ?? yearString(fromInfo: item.info) {
            texts.append(year)
        }
        let categories = item.metaTags.isEmpty ? item.tags.map(\.name) : item.metaTags
        texts.append(contentsOf: categories.prefix(maxTags))
        return texts
    }

    /// 正文：优先完整简介；trending 不返回 summary，回落到它的 info 单行串。
    static func detailText(for item: BangumiItem) -> String {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { return summary }
        return item.info.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 trending 的 info 串里捞年份，形如 `14话 / 2026年7月4日 / 导演`。
    static func yearString(fromInfo info: String) -> String? {
        guard let range = info.range(of: #"(19|20)\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return String(info[range])
    }

    static func yearString(from airDate: String) -> String? {
        let trimmed = airDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        guard year.allSatisfy(\.isNumber), year != "0000" else { return nil }
        return year
    }
}

/// 分页滚动的内容偏移量（正值 = 已向右滚过的距离）。
///
/// 由每一页各自上报（各页算出来一致）。挂在 HStack `.background` 上的单个
/// GeometryReader 量不到滚动，具名坐标系在 ScrollView 内容里也解析不到。
private struct BannerScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 首页顶部沉浸式 Banner（竞品同款结构）。
///
/// 分页靠 `ScrollView` + `.scrollTargetBehavior(.paging)`：跟手、松手才吸页，
/// 每页的视图身份绑定 item，翻页只是容器位移，文案不会瞬变、图片不会淡入。
///
/// 层叠（由底到顶）：
/// 1. 封面图（只占上部，底层，超铺 1.7 倍页宽做视差）+ 整图轻染色
/// 2. 图片底部「透明 → 实心主色」渐变，收口于图片底边
/// 3. 图片下方剩余区域：实心主色（与页面底色同色，无硬边）
/// 4. 文案（标题 / 评分行 / 简介）随页全速走，锚定 banner 底部
/// 5. 轮播 indicator 提到轮播外层，固定在左下角不随页面位移
public struct HomeHeroBanner: View {
    let items: [BangumiItem]
    let activeIndex: Int
    /// 逐条封面色板（按 item.id）；每页各用各的色，中缝是硬分割。
    let palettes: [Int: CoverColorPalette]
    var viewportHeight: CGFloat
    var topInset: CGFloat = 0
    var onChangeIndex: (Int) -> Void
    var onDominantIndexChange: (Int) -> Void
    var onTapItem: (BangumiItem) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var scrolledSlot: Int?

    public init(
        items: [BangumiItem],
        activeIndex: Int,
        palettes: [Int: CoverColorPalette],
        viewportHeight: CGFloat,
        topInset: CGFloat = 0,
        onChangeIndex: @escaping (Int) -> Void,
        onDominantIndexChange: @escaping (Int) -> Void,
        onTapItem: @escaping (BangumiItem) -> Void
    ) {
        self.items = items
        self.activeIndex = activeIndex
        self.palettes = palettes
        self.viewportHeight = viewportHeight
        self.topInset = topInset
        self.onChangeIndex = onChangeIndex
        self.onDominantIndexChange = onDominantIndexChange
        self.onTapItem = onTapItem
    }

    private var totalHeight: CGFloat {
        HomeHeroBannerLayout.totalHeight(viewportHeight: viewportHeight, topInset: topInset)
    }

    private var imageHeight: CGFloat {
        HomeHeroBannerLayout.imageHeight(totalHeight: totalHeight)
    }

    private func palette(for item: BangumiItem) -> CoverColorPalette {
        palettes[item.id] ?? .fallback
    }

    /// 页面 / scrim 收口用的实心色。
    private func solidColor(for item: BangumiItem) -> Color {
        palette(for: item).darkened.color
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            // 下拉过滚时顶部锚定屏幕、整体拉高，图片随之放大，顶部不露缝
            // （静止时 banner 顶部即全局 y=0，minY > 0 即过滚量）
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .global).minY)
                carousel(stretch: stretch)
                    .frame(height: totalHeight + stretch)
                    .offset(y: -stretch)
            }
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight)
        }
    }

    // MARK: - carousel

    @ViewBuilder
    private func carousel(stretch: CGFloat) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let originX = geo.frame(in: .global).minX
            let chrome = dominantPalette(pageWidth: width)
            ZStack(alignment: .bottomLeading) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<slotCount, id: \.self) { slot in
                            GeometryReader { pageGeo in
                                // 每页自己量到容器左缘的距离：0 = 正在屏幕上，±1 = 左右各一页。
                                let progress = (pageGeo.frame(in: .global).minX - originX) / width
                                bannerPage(
                                    item: items[HomeHeroBannerLayout.realIndex(
                                        slot: slot, itemCount: items.count
                                    )],
                                    progress: progress,
                                    pageWidth: width,
                                    stretch: stretch,
                                    chrome: chrome
                                )
                                .preference(
                                    key: BannerScrollOffsetKey.self,
                                    value: (CGFloat(slot) - progress) * width
                                )
                            }
                            .frame(width: width, height: totalHeight + stretch)
                            .id(slot)
                        }
                    }
                    .scrollTargetLayout()
                    .onPreferenceChange(BannerScrollOffsetKey.self) { offset in
                        scrollOffset = offset
                    }
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledSlot)
                .scrollIndicators(.hidden)
                .onChange(of: dominantRealIndex(pageWidth: width)) { _, dominant in
                    onDominantIndexChange(dominant)
                }
                .onChange(of: scrollOffset) { _, _ in
                    recenterIfSettled(pageWidth: width)
                }
                .onChange(of: scrolledSlot) { _, slot in
                    guard let slot else { return }
                    let real = HomeHeroBannerLayout.realIndex(slot: slot, itemCount: items.count)
                    guard real != activeIndex else { return }
                    onChangeIndex(real)
                }
                .onAppear {
                    if scrolledSlot == nil {
                        scrolledSlot = HomeHeroBannerLayout.loopStartSlot(
                            itemCount: items.count, activeIndex: activeIndex
                        )
                    }
                }

                pageBars(pageWidth: width)
                    .padding(.leading, HomeHeroBannerLayout.horizontalPadding)
                    .padding(.bottom, 10)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: totalHeight + stretch)
            .clipped()
        }
    }

    private var slotCount: Int {
        HomeHeroBannerLayout.loopedSlotCount(itemCount: items.count)
    }

    private func dominantRealIndex(pageWidth: CGFloat) -> Int {
        let slot = HomeHeroBannerLayout.dominantIndex(
            scrollOffset: scrollOffset, pageWidth: pageWidth, pageCount: slotCount
        )
        return HomeHeroBannerLayout.realIndex(slot: slot, itemCount: items.count)
    }

    /// 占屏最多那页的色板 —— banner 收口色与整页底色都用它，保证两者一致。
    private func dominantPalette(pageWidth: CGFloat) -> CoverColorPalette {
        let index = dominantRealIndex(pageWidth: pageWidth)
        guard items.indices.contains(index) else { return .fallback }
        return palette(for: items[index])
    }

    /// 停稳在段外时静默搬回中段。三段内容一致，所以搬迁不可见，
    /// 哪怕手指还按着也不会看出跳变。
    private func recenterIfSettled(pageWidth: CGFloat) {
        guard items.count > 1, pageWidth > 0 else { return }
        let slot = Int((scrollOffset / pageWidth).rounded())
        guard abs(scrollOffset - CGFloat(slot) * pageWidth) < 0.5 else { return }
        guard let target = HomeHeroBannerLayout.recenteredSlot(
            slot: slot, itemCount: items.count
        ) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrolledSlot = target }
    }

    @ViewBuilder
    private func bannerPage(
        item: BangumiItem,
        progress: CGFloat,
        pageWidth: CGFloat,
        stretch: CGFloat,
        chrome: CoverColorPalette
    ) -> some View {
        let solid = solidColor(for: item)
        // 收口色跟整页背景走，不跟本页走：否则拖到一半时左右两页的实心色带
        // 各自一色、又都对不上下方页面底色，会拼出一块 L 形硬边。
        let closing = chrome.darkened.color
        ZStack(alignment: .bottom) {
            // ①② 底层：封面（只占上部，随页视差慢跟）+ 渐变收口；下方剩余区域实心主色
            VStack(spacing: 0) {
                Color.clear
                    .frame(width: pageWidth, height: imageHeight + stretch)
                    .overlay {
                        coverImage(for: item, solid: solid)
                            .frame(
                                width: HomeHeroBannerLayout.imageOverscanWidth(pageWidth: pageWidth),
                                height: imageHeight + stretch
                            )
                            .clipped()
                            .offset(x: HomeHeroBannerLayout.parallaxOffset(
                                progress: progress, pageWidth: pageWidth
                            ))
                    }
                    .clipped()
                    .overlay {
                        // 整图轻染主色，和页面色调统一
                        solid.opacity(0.14)
                    }
                    .overlay { imageScrim(solid, closing: closing) }
                    .overlay(alignment: .top) { statusBarShade }
                closing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.65), value: palette(for: item))
            .animation(.easeInOut(duration: 0.65), value: chrome)

            // ③ 顶层：文案随页全速走，锚定底部，上缘自然压在渐变区上
            metaBlock(for: item)
                .padding(.horizontal, HomeHeroBannerLayout.horizontalPadding)
                .padding(.bottom, 10 + HomeHeroBannerLayout.pageBarReservedHeight)
        }
        .frame(width: pageWidth, height: totalHeight + stretch)
        .contentShape(Rectangle())
        .onTapGesture { onTapItem(item) }
    }

    /// 图片底部「透明 → 实心」，收口于图片底边，与下方实心区无缝。
    ///
    /// 中段仍用本页主色（拖动时左右两页的图像区色调各不相同），
    /// 但最后收口到整页底色，让图像以下不再有可见分界。
    private func imageScrim(_ solid: Color, closing: Color) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: HomeHeroBannerLayout.scrimStart),
                .init(color: solid.opacity(0.28), location: 0.66),
                .init(color: solid.opacity(0.62), location: 0.82),
                .init(color: closing.opacity(0.9), location: 0.93),
                .init(color: closing, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 状态栏区域轻压暗，保证时钟可读。
    private var statusBarShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.35),
                Color.black.opacity(0.06),
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: max(topInset + 24, 52))
    }

    @ViewBuilder
    private func coverImage(for item: BangumiItem, solid: Color) -> some View {
        RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
            solid.overlay { ProgressView().tint(.white.opacity(0.7)) }
        }
    }

    // MARK: - meta

    @ViewBuilder
    private func metaBlock(for item: BangumiItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.displayName)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(HomeHeroBannerLayout.titleLineLimit)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            metaFactsRow(for: item)

            let detail = HomeHeroBannerLayout.detailText(for: item)
            if !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(HomeHeroBannerLayout.summaryLineLimit)
                    .lineSpacing(2.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一行事实信息：★评分 · 🔥热度 · 年份 · 类型标签
    @ViewBuilder
    private func metaFactsRow(for item: BangumiItem) -> some View {
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        if item.ratingScore > 0 || item.heat > 0 || !facts.isEmpty {
            HStack(spacing: 8) {
                if item.ratingScore > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", item.ratingScore))
                    }
                }
                if item.heat > 0 {
                    if item.ratingScore > 0 { factSeparator }
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(HomeHeroBannerLayout.heatText(item.heat))
                    }
                }
                ForEach(facts, id: \.self) { text in
                    factSeparator
                    Text(text)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var factSeparator: some View {
        Text("·")
            .foregroundStyle(.white.opacity(0.4))
    }

    // MARK: - indicator

    /// 固定在左下角，不随页面位移；高亮段按连续滚动进度伸缩，所以拖到一半是中间态。
    @ViewBuilder
    private func pageBars(pageWidth: CGFloat) -> some View {
        if items.count > 1 {
            let position = pageWidth > 0 ? scrollOffset / pageWidth : 0
            HStack(spacing: HomeHeroBannerLayout.pageBarSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    let weight = HomeHeroBannerLayout.pageBarWeight(
                        position: position, index: index, itemCount: items.count
                    )
                    Capsule()
                        .fill(Color.white.opacity(0.35 + 0.65 * weight))
                        .frame(
                            width: HomeHeroBannerLayout.pageBarWidth
                                + (HomeHeroBannerLayout.pageBarActiveWidth
                                    - HomeHeroBannerLayout.pageBarWidth) * weight,
                            height: HomeHeroBannerLayout.pageBarHeight
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Banner 第 \(activeIndex + 1) / \(items.count) 页")
        }
    }
}
