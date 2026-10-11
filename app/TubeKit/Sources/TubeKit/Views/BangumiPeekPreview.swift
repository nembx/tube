import SwiftUI

/// 长按 peek 预览的布局参数与文案取值。
enum BangumiPeekLayout {
    /// 预览卡宽度。窄屏上 contextMenu 会自己再收一点，这里给的是上限。
    static let width: CGFloat = 260
    static let coverAspectRatio: CGFloat = 3.0 / 4.0
    static let contentSpacing: CGFloat = 8
    static let contentPadding: CGFloat = 14
    static let summaryLineLimit: Int = 4
    /// 事实行最多显示几项，多了会换行把卡撑高。
    static let maxFacts: Int = 3

    /// 副标题：原名与显示名不同才给，否则同一行字重复两遍。
    static func subtitle(for item: BangumiItem) -> String? {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.displayName else { return nil }
        return name
    }

    static func ratingText(for item: BangumiItem) -> String? {
        guard item.ratingScore > 0 else { return nil }
        return String(format: "%.1f", item.ratingScore)
    }

    /// 话数 → 年份 → 官方分类标签（metaTags 缺失时回落到用户标签）。
    static func factTexts(for item: BangumiItem) -> [String] {
        var texts: [String] = []
        if item.episodeCount > 0 {
            texts.append("\(item.episodeCount)话")
        }
        if let year = HomeHeroBannerLayout.yearString(from: item.airDate)
            ?? HomeHeroBannerLayout.yearString(fromInfo: item.info) {
            texts.append(year)
        }
        let categories = item.metaTags.isEmpty ? item.tags.map(\.name) : item.metaTags
        texts.append(contentsOf: categories)
        return Array(texts.prefix(maxFacts))
    }

    /// 简介：优先 summary，trending 没有就回落到 info 那串单行信息。
    /// 段落换行在这么小的卡里只会把行数吃光，压成单行。
    static func summaryText(for item: BangumiItem) -> String {
        let raw = HomeHeroBannerLayout.detailText(for: item)
        return raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// 长按资源 item 弹出的临时预览卡。
///
/// 只读：封面 + 名字 + 评分 / 事实 + 简介。要看全的走菜单里的「查看详情」。
struct BangumiPeekPreview: View {
    let item: BangumiItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            details
        }
        .frame(width: BangumiPeekLayout.width)
    }

    @ViewBuilder
    private var cover: some View {
        Color.clear
            .frame(width: BangumiPeekLayout.width)
            .aspectRatio(BangumiPeekLayout.coverAspectRatio, contentMode: .fit)
            .overlay {
                RemoteImage(url: URL(string: item.images.listBest)) {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: BangumiPeekLayout.contentSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(2)
                if let subtitle = BangumiPeekLayout.subtitle(for: item) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            factsRow

            let summary = BangumiPeekLayout.summaryText(for: item)
            if !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(BangumiPeekLayout.summaryLineLimit)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BangumiPeekLayout.contentPadding)
    }

    @ViewBuilder
    private var factsRow: some View {
        let facts = BangumiPeekLayout.factTexts(for: item)
        let rating = BangumiPeekLayout.ratingText(for: item)
        if rating != nil || !facts.isEmpty {
            HStack(spacing: 6) {
                if let rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(rating)
                    }
                    .font(.caption.weight(.bold))
                }
                Text(facts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    /// 给一个资源 item 挂长按 peek 预览。松手落在「查看详情」上才真正打开。
    func bangumiPeek(item: BangumiItem, onOpen: @escaping () -> Void) -> some View {
        contextMenu {
            Button {
                onOpen()
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }
        } preview: {
            BangumiPeekPreview(item: item)
        }
    }
}
