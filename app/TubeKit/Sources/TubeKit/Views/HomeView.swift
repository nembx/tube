import SwiftUI

/// 窄屏（iPhone）主页 —— Bangumi.tv 番剧浏览。
///
/// 层叠：全页实心主色底 → Banner 图（顶区）→ List（透明底）盖在上面。
/// Banner 内自带「透明→实心」scrim，底部与页面实心色对齐，滚动无硬边。
///
/// 宽屏主页见 `RegularHomeView`；宽窄屏分开维护，不做同一套自适应。
public struct HomeView: View {
    @Bindable var model: HomeViewModel
    @Bindable var history: HistoryStore
    var onTapItem: (BangumiItem) -> Void
    var onTapSection: (HomeSection) -> Void
    var onTapHistoryEntry: (WatchHistoryEntry) -> Void
    var onRemoveHistoryEntry: (WatchHistoryEntry) -> Void
    var onTapSearch: () -> Void

    /// 当前占屏最多的 banner 页 —— 全局底色跟它走，跨半页即切，回弹也跟着变回。
    @State private var dominantBannerIndex: Int = 0

    public init(
        model: HomeViewModel,
        history: HistoryStore,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSection: @escaping (HomeSection) -> Void,
        onTapHistoryEntry: @escaping (WatchHistoryEntry) -> Void,
        onRemoveHistoryEntry: @escaping (WatchHistoryEntry) -> Void,
        onTapSearch: @escaping () -> Void
    ) {
        self.model = model
        self.history = history
        self.onTapItem = onTapItem
        self.onTapSection = onTapSection
        self.onTapHistoryEntry = onTapHistoryEntry
        self.onRemoveHistoryEntry = onRemoveHistoryEntry
        self.onTapSearch = onTapSearch
    }

    /// 占屏最多那页的色板；色板尚未取到时回落到默认深紫。
    private var dominantPalette: CoverColorPalette {
        guard model.bannerItems.indices.contains(dominantBannerIndex) else {
            return model.activeBannerPalette
        }
        return model.bannerPalettes[model.bannerItems[dominantBannerIndex].id] ?? .fallback
    }

    public var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let viewportHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let palette = dominantPalette
            let solid = palette.darkened.color

            ZStack {
                // 全页实心底色（与 Banner scrim 收口同色）
                solid
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.65), value: palette)

                List {
                    ScrollToTopAnchor()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if !model.bannerItems.isEmpty {
                        HomeHeroBanner(
                            items: model.bannerItems,
                            activeIndex: model.activeBannerIndex,
                            palettes: model.bannerPalettes,
                            viewportHeight: viewportHeight,
                            topInset: topInset,
                            onChangeIndex: { model.setActiveBannerIndex($0) },
                            onDominantIndexChange: { dominantBannerIndex = $0 },
                            onTapItem: onTapItem
                        )
                        .listRowInsets(EdgeInsets(
                            top: -topInset,
                            leading: 0,
                            bottom: 0,
                            trailing: 0
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if !history.continueWatching.isEmpty {
                        ContinueWatchingSection(
                            entries: history.continueWatching,
                            onTapEntry: onTapHistoryEntry,
                            onRemoveEntry: onRemoveHistoryEntry
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(model.sections) { content in
                        BangumiSectionRow(
                            content: content,
                            cardWidth: BangumiSectionLayout.cardWidth,
                            onTapItem: onTapItem,
                            onTapSeeAll: { onTapSection(content.section) },
                            onRetry: {
                                Task { await model.retrySection(content.id) }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .task(id: content.id) {
                            await model.loadSectionIfNeeded(content.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollToTop()
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // 热门优先；历史刷新与其余色板不挡首屏
            async let initial: Void = model.loadInitialIfNeeded()
            try? history.refresh()
            await initial
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
        // 搜索从 dock 挪到这里：首页右上角，压在 banner 上。
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onTapSearch) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索")
                // toolbar 挂在页面 dark 上下文外面，拿到的是系统明暗。
                // 首页恒定深色底，浅色模式下这个 icon 会被算成黑的压在 banner 上。
                .environment(\.colorScheme, .dark)
            }
        }
    }
}
