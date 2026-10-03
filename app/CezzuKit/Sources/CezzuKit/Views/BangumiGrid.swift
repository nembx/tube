import SwiftUI

/// 番剧宫格布局参数。按「固定 item 首选宽度」让 `LazyVGrid` 自适应列数。
enum BangumiGridLayout {
    static let horizontalSpacing: CGFloat = 14
    static let verticalSpacing: CGFloat = 18
    /// 单卡最小宽度。列数 = 容器能放下多少个 ≥ 此宽度的 cell。
    static let preferredItemWidth: CGFloat = 150
    /// 单卡最大宽度。剩余空间不够再塞一列时，cell 最多涨到这里，避免被拉成海报墙。
    static let maximumItemWidth: CGFloat = 200

    static var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: preferredItemWidth, maximum: maximumItemWidth),
                spacing: horizontalSpacing,
                alignment: .top
            )
        ]
    }

    /// 根据容器可用宽度估算列数（测试 / 调试用；真实布局交给 `GridItem.adaptive`）。
    ///
    /// 公式：`n * preferred + (n - 1) * spacing ≤ width`
    /// → `n ≤ (width + spacing) / (preferred + spacing)`
    static func columnCount(forWidth width: CGFloat) -> Int {
        let minimumColumnCount = 1
        guard width.isFinite, width > 0 else { return minimumColumnCount }
        let unit = preferredItemWidth + horizontalSpacing
        let raw = Int(floor((width + horizontalSpacing) / unit))
        return max(minimumColumnCount, raw)
    }
}

/// 响应式番剧宫格。用 `GridItem.adaptive` 按首选宽度自动算列数；
/// footer 放在 grid 下方，避免再依赖 GeometryReader 量宽（ScrollView 里容易量错、锁死 2 列）。
public struct BangumiGrid<Footer: View>: View {
    private let items: [BangumiItem]
    private let onTapItem: (BangumiItem) -> Void
    private let onLoadMore: (BangumiItem) async -> Void
    private let footer: Footer

    public init(
        items: [BangumiItem],
        onTapItem: @escaping (BangumiItem) -> Void,
        onLoadMore: @escaping (BangumiItem) async -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self.items = items
        self.onTapItem = onTapItem
        self.onLoadMore = onLoadMore
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BangumiGridLayout.verticalSpacing) {
            LazyVGrid(
                columns: BangumiGridLayout.columns,
                alignment: .leading,
                spacing: BangumiGridLayout.verticalSpacing
            ) {
                ForEach(items) { item in
                    Button {
                        onTapItem(item)
                    } label: {
                        BangumiCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .bangumiPeek(item: item) { onTapItem(item) }
                    .task {
                        await onLoadMore(item)
                    }
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
