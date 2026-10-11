import SwiftUI

/// 番剧元数据详情页 —— 进入该页之前由 HomeView 选中一个 BangumiItem。
///
/// 用户在这里看 Bangumi 提供的元数据（封面 / 简介 / 评分 / tags / 日期）。
/// 底部一个「在规则源中搜索」按钮 —— 把番剧名当关键字 push 回常规搜索流程。
public struct BangumiInfoView: View {
    let item: BangumiItem
    var onSearchInRules: (String) -> Void

    public init(
        item: BangumiItem,
        onSearchInRules: @escaping (String) -> Void
    ) {
        self.item = item
        self.onSearchInRules = onSearchInRules
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !item.summary.isEmpty {
                    section(title: "简介") {
                        Text(item.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !item.tags.isEmpty {
                    section(title: "标签") {
                        tagFlow
                    }
                }
                actionBar
            }
            .padding(20)
        }
        .navigationTitle(item.displayName)
    }

    // MARK: - header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
                .frame(width: 140)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayName)
                    .font(.title2.bold())
                    .lineLimit(3)
                if item.nameCn != item.name && !item.name.isEmpty {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if item.ratingScore > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", item.ratingScore))
                            .font(.headline)
                        if item.rank > 0 {
                            Text("· Rank #\(item.rank)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !item.airDate.isEmpty {
                    Label(item.airDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: item.images.best)
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                ZStack {
                    Color.secondary.opacity(0.08)
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            case .empty:
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                }
            @unknown default:
                Color.secondary.opacity(0.08)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - sections

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            GlassPanel { content() }
        }
    }

    @ViewBuilder
    private var tagFlow: some View {
        WrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(item.tags.prefix(20), id: \.name) { tag in
                Text(tag.name)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassBackground(in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            GlassPrimaryButton("在规则源中搜索", systemImage: "magnifyingglass") {
                onSearchInRules(item.displayName)
            }
            Text("将用「\(item.displayName)」作为关键字在你已安装的规则中搜索。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - WrapLayout

/// 一个最简单的 flow / wrap layout，用 SwiftUI Layout protocol。仅给 tag 列表用。
struct WrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let row = rows.count - 1
            let needed = rows[row] == 0 ? size.width : rows[row] + spacing + size.width
            if needed > maxWidth && rows[row] > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[row] = needed
                rowHeights[row] = max(rowHeights[row], size.height)
            }
        }
        let totalHeight = rowHeights.reduce(0, +) + lineSpacing * CGFloat(max(rowHeights.count - 1, 0))
        let widestRow = rows.max() ?? 0
        return CGSize(width: min(widestRow, maxWidth), height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
