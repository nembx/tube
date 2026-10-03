import Foundation

/// Bangumi 搜索的可选筛选条件。对应 `POST /v0/search/subjects` 的 `filter` 字段。
///
/// 所有字段都是可选的；不设置就不参与筛选。空数组 / nil 会从最终 body 里被剔除。
public struct BangumiSearchFilter: Sendable, Equatable, Hashable {
    /// 多个 tag 之间是 `且` 关系；用 `-标签` 形式排除（API 原生支持）。
    public var tags: [String]
    /// 评分下限（包含）。`nil` 表示不限。
    public var ratingMin: Double?
    /// 评分上限（包含）。`nil` 表示不限。
    public var ratingMax: Double?
    /// 播出日期下限（包含），`YYYY-MM-DD`。`nil` 表示不限。
    public var airDateAfter: String?
    /// 播出日期上限（不含），`YYYY-MM-DD`。`nil` 表示不限。
    public var airDateBefore: String?
    /// 是否包含 R18 条目。
    /// - `false`（默认）→ 仅返回非 R18
    /// - `true` → 返回包含 R18 的所有结果（API 文档：默认 / null 时返回所有；这里把 true 映射成"显式不限制"）
    public var includeNSFW: Bool

    public init(
        tags: [String] = [],
        ratingMin: Double? = nil,
        ratingMax: Double? = nil,
        airDateAfter: String? = nil,
        airDateBefore: String? = nil,
        includeNSFW: Bool = false
    ) {
        self.tags = tags
        self.ratingMin = ratingMin
        self.ratingMax = ratingMax
        self.airDateAfter = airDateAfter
        self.airDateBefore = airDateBefore
        self.includeNSFW = includeNSFW
    }

    /// 默认筛选：无 tag、无评分 / 日期范围、不含 R18。
    public static let `default` = BangumiSearchFilter()

    /// 是否所有字段都为默认值。UI 用来决定是否显示"已启用筛选"提示。
    public var isDefault: Bool {
        self == .default
    }

    /// 是否带了只有 `/v0/search/subjects` 才支持的收窄条件。
    ///
    /// 旧接口只认 `type` + 关键词，也不返回 tags / 评分明细，客户端补筛都补不了。
    /// 带这些条件时就别走旧通道 —— 拿回来的条目无法参与筛选，混进结果里是错的。
    /// 注意 `includeNSFW` 不算：它在匿名请求下本来就会被服务端忽略。
    public var hasNarrowingConstraints: Bool {
        !tags.isEmpty
            || ratingMin != nil
            || ratingMax != nil
            || airDateAfter != nil
            || airDateBefore != nil
    }

    /// 用一个全角年（如 2020）便捷地填充 air_date 上下限：`>=YYYY-01-01` & `<YYYY+1-01-01`。
    public mutating func setYearRange(min minYear: Int?, max maxYear: Int?) {
        if let minYear, minYear > 0 {
            airDateAfter = String(format: "%04d-01-01", minYear)
        } else {
            airDateAfter = nil
        }
        if let maxYear, maxYear > 0 {
            airDateBefore = String(format: "%04d-01-01", maxYear + 1)
        } else {
            airDateBefore = nil
        }
    }
}
