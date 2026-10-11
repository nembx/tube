import Foundation

/// 一页搜索结果，外加翻页所需的游标。
///
/// 存在的理由：第一页的结果是 v0 与旧接口两条通道合流出来的，条目数不等于
/// v0 自己消费掉的条数。调用方如果继续用 `results.count` 当下一页的 offset，
/// 会跳过若干条 v0 结果。`nextOffset` 始终只跟着 v0 走。
public struct BangumiSearchPage: Sendable, Equatable {
    public let items: [BangumiItem]
    /// 下一页要传给 `/v0/search/subjects` 的 offset。
    public let nextOffset: Int
    public let hasMore: Bool

    public init(items: [BangumiItem], nextOffset: Int, hasMore: Bool) {
        self.items = items
        self.nextOffset = nextOffset
        self.hasMore = hasMore
    }

    public static let empty = BangumiSearchPage(items: [], nextOffset: 0, hasMore: false)
}

// MARK: - Merge

extension BangumiSearchPage {
    /// 把旧接口的召回并进 v0 的结果。
    ///
    /// 规则（每一条都是为了让合流结果可预测、可单测）：
    ///   1. v0 结果保持原序，作为主体 —— 它有 tags / infobox，是权威来源
    ///   2. 旧接口结果里剔除 v0 已经给过的 id
    ///   3. 剩下的只保留标题命中关键词的；summary 命中的那些既没有元数据，
    ///      又会把排序搅乱，直接丢掉
    ///   4. 命中的按旧接口原序置顶 —— 它们是 v0 完全召回不到的条目，
    ///      排在第 20 位等于没找到
    static func merge(
        v0Items: [BangumiItem],
        legacyItems: [BangumiItem],
        keyword: String
    ) -> [BangumiItem] {
        let needle = normalized(keyword)
        guard !needle.isEmpty else { return v0Items }
        let known = Set(v0Items.map(\.id))
        let promoted = legacyItems.filter { item in
            guard !known.contains(item.id) else { return false }
            return normalized(item.name).contains(needle)
                || normalized(item.nameCn).contains(needle)
        }
        return promoted + v0Items
    }

    /// 标题匹配用的归一化：忽略大小写与空白。
    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace }
    }
}
