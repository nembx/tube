import SwiftUI

/// 窄屏（iPhone）搜索屏 —— 影院式暗底：大搜索框 + 一行可展开的筛选 chip，
/// 未搜索时是"最近搜索 / 常用标签 / 首页分区"三段浏览，不是一张空面板。
///
/// 宽屏搜索见 `RegularSearchView`；宽窄屏分开维护，共用 `Views/Search/SearchChrome.swift` 的元件。
public struct SearchView: View {
    @Bindable var model: SearchViewModel
    @Bindable var browseModel: HomeViewModel
    var onTapItem: (BangumiItem) -> Void
    var onTapSection: (HomeSection) -> Void
    @FocusState private var isInputFocused: Bool
    @FocusState private var isTagDraftFocused: Bool
    @State private var expandedFacet: SearchFacet?
    @State private var newTagDraft: String = ""

    private let metrics = SearchMetrics.compact

    /// 最近搜索一次最多摆多少个。
    private static let historyLimit: Int = 10

    public init(
        model: SearchViewModel,
        browseModel: HomeViewModel,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSection: @escaping (HomeSection) -> Void
    ) {
        self.model = model
        self.browseModel = browseModel
        self.onTapItem = onTapItem
        self.onTapSection = onTapSection
    }

    public var body: some View {
        ZStack(alignment: .top) {
            SearchAmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollToTopAnchor()
                    LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        header
                        SearchField(
                            text: $model.text,
                            height: metrics.fieldHeight,
                            prompt: "番剧名、原名或关键词",
                            isFocused: $isInputFocused,
                            onSubmit: submit,
                            onChange: { model.textChanged() },
                            onClear: { model.clearText() }
                        )
                        SearchFilterBar(
                            model: model,
                            expandedFacet: $expandedFacet,
                            newTagDraft: $newTagDraft,
                            isTagDraftFocused: $isTagDraftFocused
                        )
                        content
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
            }
            .scrollIndicators(.never)
            .scrollToTop()
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }

    private func submit() {
        isInputFocused = false
        Task { await model.submit() }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SEARCH")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(SearchStyle.textTertiary)
            Text("找番")
                .font(.system(size: metrics.titleSize, weight: .bold))
                .foregroundStyle(SearchStyle.textPrimary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching && model.results.isEmpty {
            BangumiSkeletonGrid()
        } else if let error = model.lastError, model.results.isEmpty {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "搜索失败",
                message: error.userMessage,
                tone: .warning,
                actionTitle: "重试",
                action: submit
            )
        } else if model.hasSearched && model.results.isEmpty {
            noMatchState
        } else if !model.results.isEmpty {
            results
        } else {
            idle
        }
    }

    @ViewBuilder
    private var noMatchState: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "没有找到匹配的番剧",
                message: "换个说法，或松一松下面的筛选。"
            )
            SearchTagCloudSection(model: model, title: "换个标签试试")
        }
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchSectionHeader(eyebrow: "RESULTS", title: "搜索结果") {
                Text(
                    SearchResultsSummary.text(
                        count: model.results.count,
                        hasMore: model.hasMore,
                        keyword: model.text
                    )
                )
                .font(.caption)
                .foregroundStyle(SearchStyle.textTertiary)
                .lineLimit(1)
            }
            BangumiGrid(
                items: model.results,
                onTapItem: onTapItem,
                onLoadMore: { item in
                    await model.loadMoreIfNeeded(currentItem: item)
                }
            ) {
                if model.isLoadingMore {
                    BangumiSkeletonGrid(placeholderCount: 4)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// 未发起搜索：最近搜索 → 常用标签 → 与首页一致的分区浏览。
    @ViewBuilder
    private var idle: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            SearchHistorySection(model: model, limit: Self.historyLimit) { keyword in
                isInputFocused = false
                Task { await model.applyHistory(keyword) }
            }
            SearchTagCloudSection(model: model, title: "热门标签")

            ForEach(browseModel.sections) { content in
                BangumiSectionRow(
                    content: content,
                    cardWidth: metrics.cardWidth,
                    onTapItem: onTapItem,
                    onTapSeeAll: { onTapSection(content.section) },
                    onRetry: {
                        Task { await browseModel.retrySection(content.id) }
                    }
                )
                .task(id: content.id) {
                    await browseModel.loadSectionIfNeeded(content.id)
                }
            }
        }
        .task { await browseModel.loadInitialIfNeeded() }
    }
}
