import SwiftUI

/// 宽屏（macOS / iPad）主页 —— 影院式全幅首页。
///
/// Banner 吃掉整个视口（顶栏从它上面穿过去），往下滚时封面色渐隐进影院黑，
/// 分区流浮在黑底上。一级入口不在这里，在外壳的悬浮顶栏 `RegularTopBar`。
///
/// 窄屏主页见 `HomeView`。两者共用 `HomeViewModel`，chrome 分开维护。
public struct RegularHomeView: View {
    @Bindable var model: HomeViewModel
    @Bindable var history: HistoryStore
    var onTapItem: (BangumiItem) -> Void
    var onTapSection: (HomeSection) -> Void
    var onTapHistoryEntry: (WatchHistoryEntry) -> Void
    var onRemoveHistoryEntry: (WatchHistoryEntry) -> Void

    /// 当前正播的 banner 页 —— 全局底色跟它走，热门那一行也据此高亮同一条。
    @State private var dominantBannerIndex: Int = 0

    public init(
        model: HomeViewModel,
        history: HistoryStore,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSection: @escaping (HomeSection) -> Void,
        onTapHistoryEntry: @escaping (WatchHistoryEntry) -> Void,
        onRemoveHistoryEntry: @escaping (WatchHistoryEntry) -> Void
    ) {
        self.model = model
        self.history = history
        self.onTapItem = onTapItem
        self.onTapSection = onTapSection
        self.onTapHistoryEntry = onTapHistoryEntry
        self.onRemoveHistoryEntry = onRemoveHistoryEntry
    }

    private var dominantPalette: CoverColorPalette {
        guard model.bannerItems.indices.contains(dominantBannerIndex) else {
            return model.activeBannerPalette
        }
        return model.bannerPalettes[model.bannerItems[dominantBannerIndex].id] ?? .fallback
    }

    public var body: some View {
        GeometryReader { geo in
            let palette = dominantPalette

            ZStack {
                RegularShellLayout.cinemaBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ScrollToTopAnchor()
                        if model.bannerItems.isEmpty {
                            heroPlaceholder(height: RegularHomeHeroLayout.contentHeight(
                                viewportHeight: geo.size.height
                            ))
                        } else {
                            RegularHomeHeroBanner(
                                items: model.bannerItems,
                                activeIndex: model.activeBannerIndex,
                                palettes: model.bannerPalettes,
                                viewportHeight: geo.size.height,
                                onChangeIndex: { index in
                                    dominantBannerIndex = index
                                    model.setActiveBannerIndex(index)
                                },
                                onTapItem: onTapItem
                            )
                        }

                        rows
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
                .scrollToTop()
            }
            .animation(.easeInOut(duration: 0.65), value: palette)
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
        .task {
            async let initial: Void = model.loadInitialIfNeeded()
            try? history.refresh()
            await initial
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !history.continueWatching.isEmpty {
                ContinueWatchingSection(
                    entries: history.continueWatching,
                    subtitle: "CONTINUE WATCHING",
                    onTapEntry: onTapHistoryEntry,
                    onRemoveEntry: onRemoveHistoryEntry,
                    fallbackCoverURL: { model.historyCoverURL(for: $0) },
                    onNeedsFallbackCover: { model.resolveHistoryCoverIfNeeded(for: $0) }
                )
                .padding(.horizontal, RegularHomeHeroLayout.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            ForEach(model.sections) { content in
                BangumiSectionRow(
                    content: content,
                    cardWidth: BangumiSectionLayout.regularCardWidth,
                    subtitle: content.section.tag.isEmpty ? "TOP ANIME VAULT" : nil,
                    onTapItem: onTapItem,
                    onTapSeeAll: { onTapSection(content.section) },
                    onRetry: {
                        Task { await model.retrySection(content.id) }
                    }
                )
                .padding(.horizontal, RegularHomeHeroLayout.horizontalPadding)
                .padding(.vertical, 16)
                .task(id: content.id) {
                    await model.loadSectionIfNeeded(content.id)
                }
            }
        }
    }

    /// Banner 还没数据时不要塌成 0 高，否则分区流会先顶到窗口最上沿再被挤下去。
    @ViewBuilder
    private func heroPlaceholder(height: CGFloat) -> some View {
        LinearGradient(
            colors: [
                CoverColorPalette.fallback.darkened.color,
                RegularShellLayout.cinemaBackground,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .overlay { ProgressView().tint(.white.opacity(0.6)) }
    }
}
