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
            // 浏览分区流的首屏预热跟「有没有搜索上下文」走，不能挂在分区行自己身上 ——
            // 行是懒建的，挂上去就等于谁先滚到谁才触发。
            .task(id: showsBrowse) {
                guard showsBrowse else { return }
                await browseModel.loadInitialIfNeeded()
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }

    /// 没有任何搜索上下文：页面底部接的是与首页一致的浏览分区流。
    /// 与 `content` 的分支顺序一致 —— 搜索中 / 出错 / 无结果都不算。
    private var showsBrowse: Bool {
        model.results.isEmpty && !model.isSearching && model.lastError == nil && !model.hasSearched
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
    ///
    /// 这几段必须平铺成外层 `LazyVStack` 的直接子项，不能再包一层 `VStack`：
    /// 普通 VStack 在懒栈里只算**一个**单元，push 进来那一帧会把 16 个分区行、
    /// 几百张海报卡（每张还挂着长按预览）一次铺完，紧接着 16 路 `.task` 同时发请求、
    /// 同时回写 `sections` 让整棵树重算 —— 点搜索先卡一下就是这么来的。
    /// 平铺之后行只在滚到眼前时才建，分区也只加载视口里的那几个，和首页一致。
    @ViewBuilder
    private var idle: some View {
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
}
