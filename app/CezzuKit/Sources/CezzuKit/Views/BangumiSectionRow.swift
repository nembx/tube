import SwiftUI

/// 横向分区行的布局参数。
enum BangumiSectionLayout {
    static let cardWidth: CGFloat = 130
    /// 宽屏（macOS / iPad）卡宽 —— 窄屏那档在大窗口里小得像缩略图。
    static let regularCardWidth: CGFloat = 182
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 22
    static let headerBottomPadding: CGFloat = 12
    static let skeletonCount: Int = 4

    /// 单卡固定高度：封面（按 3:4）+ 间距 + 标题区。
    /// 给横向 ScrollView 明确高度，避免嵌套 ScrollView 在启动时布局递归 / 高度为 0。
    static var cardHeight: CGFloat {
        cardHeight(cardWidth: cardWidth)
    }

    static func cardHeight(cardWidth: CGFloat) -> CGFloat {
        let coverHeight = cardWidth / BangumiCardLayout.coverAspectRatio
        return coverHeight + BangumiCardLayout.spacing + BangumiCardLayout.titleHeight
    }
}

/// 首页 / 搜索 idle 态的分区行：标题 +「查看全部」+ 横向海报滚动。
public struct BangumiSectionRow: View {
    let content: HomeSectionContent
    let cardWidth: CGFloat
    /// 标题旁边那行拉丁副标题。只有宽屏会给，窄屏传 nil 保持原样。
    let subtitle: String?
    var onTapItem: (BangumiItem) -> Void
    var onTapSeeAll: () -> Void
    var onRetry: (() -> Void)?

    public init(
        content: HomeSectionContent,
        cardWidth: CGFloat,
        subtitle: String? = nil,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSeeAll: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.content = content
        self.cardWidth = cardWidth
        self.subtitle = subtitle
        self.onTapItem = onTapItem
        self.onTapSeeAll = onTapSeeAll
        self.onRetry = onRetry
    }

    private var cardHeight: CGFloat {
        BangumiSectionLayout.cardHeight(cardWidth: cardWidth)
    }

    /// 卡片 hover 时会上浮，行容器得把那段高度让出来，否则顶部会被裁掉。
    private var rowHeight: CGFloat {
        cardHeight + BangumiCardLayout.hoverLift
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, BangumiSectionLayout.headerBottomPadding)
            bodyContent
                .frame(height: rowHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(content.section.title)
                .font(.title3.bold())
                .tracking(subtitle == nil ? 0 : 2)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onTapSeeAll) {
                HStack(spacing: 4) {
                    Text("查看全部")
                    Image(systemName: subtitle == nil ? "chevron.right" : "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看全部\(content.section.title)")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if content.isLoading && content.items.isEmpty {
            skeletonRow
        } else if content.loadFailed && content.items.isEmpty {
            failedRow
        } else if content.items.isEmpty {
            emptyRow
        } else {
            itemsRow
        }
    }

    @ViewBuilder
    private var itemsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // 每区最多 20 条，用 HStack 即可；LazyHStack 在嵌套 ScrollView 里更容易量高失败。
            HStack(alignment: .top, spacing: BangumiSectionLayout.cardSpacing) {
                ForEach(content.items) { item in
                    Button {
                        onTapItem(item)
                    } label: {
                        BangumiCard(item: item)
                            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .bangumiPeek(item: item) { onTapItem(item) }
                }
            }
            .padding(.top, BangumiCardLayout.hoverLift)
        }
    }

    @ViewBuilder
    private var skeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: BangumiSectionLayout.cardSpacing) {
                ForEach(0..<BangumiSectionLayout.skeletonCount, id: \.self) { _ in
                    BangumiCardSkeleton()
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                }
            }
            .padding(.top, BangumiCardLayout.hoverLift)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var failedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text(content.lastError?.userMessage ?? "加载失败")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let onRetry {
                Button("重试", action: onRetry)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var emptyRow: some View {
        Text("暂无内容")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
