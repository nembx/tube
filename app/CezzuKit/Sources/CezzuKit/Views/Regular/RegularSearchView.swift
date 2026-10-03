import SwiftUI

/// 宽屏（macOS / iPad）搜索屏 —— 与首页同一套影院式外观：
/// 居中的大搜索框 + 一行可展开的筛选 chip，未搜索时接首页分区流，不再是一张空状态。
///
/// 窄屏搜索见 `SearchView`。两者分开维护，共用 `Views/Search/SearchChrome.swift` 的元件。
public struct RegularSearchView: View {
    @Bindable var model: SearchViewModel
    @Bindable var browseModel: HomeViewModel
    var onTapItem: (BangumiItem) -> Void
    var onTapSection: (HomeSection) -> Void
    @FocusState private var isInputFocused: Bool
    @FocusState private var isTagDraftFocused: Bool
    @State private var expandedFacet: SearchFacet?
    @State private var newTagDraft: String = ""

    private let metrics = SearchMetrics.regular

    /// 搜索框在大窗口里不该拉满一整屏宽，越长越难扫读。
    private static let fieldMaxWidth: CGFloat = 720
    /// 最近搜索一次最多摆多少个。
    private static let historyLimit: Int = 12

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
                        .frame(maxWidth: Self.fieldMaxWidth, alignment: .leading)
                        SearchFilterBar(
                            model: model,
                            expandedFacet: $expandedFacet,
                            newTagDraft: $newTagDraft,
                            isTagDraftFocused: $isTagDraftFocused
                        )
                        content
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("SEARCH")
                .font(.system(size: 12, weight: .semibold))
                .tracking(3)
                .foregroundStyle(SearchStyle.textTertiary)
            Text("找番")
                .font(.system(size: metrics.titleSize, weight: .bold))
                .tracking(2)
                .foregroundStyle(SearchStyle.textPrimary)
            Text("按番剧名检索，或用标签 / 评分 / 年代圈定范围。")
                .font(.subheadline)
                .foregroundStyle(SearchStyle.textSecondary)
        }
        .padding(.top, 12)
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
                message: "换个说法，或松一松上面的筛选。"
            )
            SearchTagCloudSection(model: model, title: "换个标签试试")
        }
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
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
