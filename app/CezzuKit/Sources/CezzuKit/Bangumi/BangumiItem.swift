import Foundation

/// Bangumi.tv 番剧条目（subject type=2）。
///
/// 这是 Cezzu 主页 / 元数据详情页用的核心模型。
/// 数据来自 https://api.bgm.tv/v0/search/subjects （旧 API）
/// 与 https://next.bgm.tv/p1/trending/subjects（新 API）。
/// 两个 API 返回的字段大同小异，但有几处差异由本类型的自定义 Codable 处理：
///   - `name_cn` 在新 API 里也叫 `nameCN`；缺失时回落到 `name`
///   - `rating.score` / `rating.rank` 在某些条目里可能为 `null`
///   - `images` 在不存在时回落到顶层 `image`（旧字段）
public struct BangumiItem: Hashable, Sendable, Identifiable, Codable {
    public let id: Int
    public let name: String
    public let nameCn: String
    public let summary: String
    public let airDate: String
    public let rank: Int
    public let ratingScore: Double
    public let ratingTotal: Int
    public let eps: Int
    public let platform: String
    public let episodeDuration: String
    public let images: BangumiImages
    public let tags: [BangumiTag]
    /// trending 接口的单行简介：`14话 / 2026年7月4日 / 导演 / 原作 / 人设`。
    public let info: String
    /// 官方分类标签（trending `metaTags` / subject `meta_tags`），如 `["TV","日本","漫画改"]`。
    public let metaTags: [String]
    /// subject 接口的 `total_episodes`；`eps` 在很多条目上是 0，它才是真正的话数。
    public let totalEpisodes: Int
    /// subject 接口的收藏分布（在看 / 想看 / 看过 …），仅详情接口返回。
    public let collection: BangumiCollection?
    /// subject 接口的 infobox 全量条目（放送星期、官网、导演、动画制作 …）。
    public let infobox: [BangumiInfoboxEntry]
    /// trending 榜单的热度值（来自条目外层 `count`），只有热门接口有。
    public private(set) var heat: Int

    public init(
        id: Int,
        name: String,
        nameCn: String,
        summary: String,
        airDate: String,
        rank: Int,
        ratingScore: Double,
        images: BangumiImages,
        tags: [BangumiTag],
        ratingTotal: Int = 0,
        eps: Int = 0,
        platform: String = "",
        episodeDuration: String = "",
        info: String = "",
        metaTags: [String] = [],
        totalEpisodes: Int = 0,
        collection: BangumiCollection? = nil,
        infobox: [BangumiInfoboxEntry] = [],
        heat: Int = 0
    ) {
        self.id = id
        self.name = name
        self.nameCn = nameCn
        self.summary = summary
        self.airDate = airDate
        self.rank = rank
        self.ratingScore = ratingScore
        self.ratingTotal = ratingTotal
        self.eps = eps
        self.platform = platform
        self.episodeDuration = episodeDuration
        self.images = images
        self.tags = tags
        self.info = info
        self.metaTags = metaTags
        self.totalEpisodes = totalEpisodes
        self.collection = collection
        self.infobox = infobox
        self.heat = heat
    }

    /// 显示名 —— 优先中文名，没有就用日文名。
    public var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    /// 实际话数 —— `total_episodes` 优先，回落到 `eps`。
    public var episodeCount: Int {
        totalEpisodes > 0 ? totalEpisodes : eps
    }

    /// trending 榜单外层的 `count` 不在 subject 里，解码后由调用方回填。
    public func withHeat(_ value: Int) -> BangumiItem {
        var copy = self
        copy.heat = value
        return copy
    }

    /// 取 infobox 里第一个匹配 key 的值。
    public func infoboxValue(forAnyOf keys: [String]) -> String? {
        for key in keys {
            if let hit = infobox.first(where: { $0.key == key })?.value, !hit.isEmpty {
                return hit
            }
        }
        return nil
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameCn = "name_cn"
        case nameCNCamel = "nameCN"     // next.bgm.tv 偶尔用驼峰
        case summary
        case date
        case airDate
        case images
        case image                       // 旧 API 顶层 image 字段
        case rating
        case tags
        case eps
        case platform
        case infobox
        case info
        case metaTags                    // next.bgm.tv 驼峰
        case metaTagsSnake = "meta_tags" // api.bgm.tv 蛇形
        case totalEpisodes = "total_episodes"
        case collection
        case heat
    }

    private enum RatingKeys: String, CodingKey {
        case rank
        case score
        case total
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""

        // name_cn 优先 snake，再 camel，最后回落到 name
        let snakeCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        let camelCn = (try? c.decode(String.self, forKey: .nameCNCamel)) ?? ""
        let chosenCn = !snakeCn.isEmpty ? snakeCn : camelCn
        self.nameCn = chosenCn.isEmpty ? self.name : chosenCn

        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""

        // 旧 API 用 `date`，新 API 也用 `date`，但有些种子用 `airDate`
        let snakeDate = (try? c.decode(String.self, forKey: .date)) ?? ""
        let camelDate = (try? c.decode(String.self, forKey: .airDate)) ?? ""
        self.airDate = !snakeDate.isEmpty ? snakeDate : camelDate

        // images：优先嵌套 dict，没有就把顶层 image 字段塞进 large
        if let nested = try? c.decode(BangumiImages.self, forKey: .images) {
            self.images = nested
        } else if let flat = try? c.decode(String.self, forKey: .image) {
            self.images = BangumiImages(large: flat, common: flat, medium: flat, small: flat, grid: flat)
        } else {
            self.images = BangumiImages.empty
        }

        // rating 子树
        if let rc = try? c.nestedContainer(keyedBy: RatingKeys.self, forKey: .rating) {
            self.rank = (try? rc.decode(Int.self, forKey: .rank)) ?? 0
            self.ratingScore = (try? rc.decode(Double.self, forKey: .score)) ?? 0.0
            self.ratingTotal = (try? rc.decode(Int.self, forKey: .total)) ?? 0
        } else {
            self.rank = 0
            self.ratingScore = 0.0
            self.ratingTotal = 0
        }

        // tags：缺失时空数组
        self.tags = (try? c.decode([BangumiTag].self, forKey: .tags)) ?? []

        // eps / platform：仅完整 subject 接口返回
        self.eps = (try? c.decode(Int.self, forKey: .eps)) ?? 0
        self.platform = (try? c.decode(String.self, forKey: .platform)) ?? ""

        // infobox 全量保留；片长单独提一份（剧场版用 "片长"，TV 可能用 "每集时长"）
        self.infobox = (try? c.decode([BangumiInfoboxEntry].self, forKey: .infobox)) ?? []
        self.episodeDuration = self.infobox.first(where: {
            $0.key == "片长" || $0.key == "每集时长" || $0.key == "时长"
        })?.value ?? ""

        self.info = (try? c.decode(String.self, forKey: .info)) ?? ""

        let camelMeta = (try? c.decode([String].self, forKey: .metaTags)) ?? []
        let snakeMeta = (try? c.decode([String].self, forKey: .metaTagsSnake)) ?? []
        self.metaTags = camelMeta.isEmpty ? snakeMeta : camelMeta

        self.totalEpisodes = (try? c.decode(Int.self, forKey: .totalEpisodes)) ?? 0
        self.collection = try? c.decode(BangumiCollection.self, forKey: .collection)
        // trending 的热度在条目外层，解码不到就是 0，由 API client 回填
        self.heat = (try? c.decode(Int.self, forKey: .heat)) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        // 写入用规范 snake_case，方便缓存 / 调试。
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(nameCn, forKey: .nameCn)
        try c.encode(summary, forKey: .summary)
        try c.encode(airDate, forKey: .date)
        try c.encode(images, forKey: .images)
        try c.encode(tags, forKey: .tags)
        try c.encode(eps, forKey: .eps)
        try c.encode(platform, forKey: .platform)
        try c.encode(info, forKey: .info)
        try c.encode(metaTags, forKey: .metaTags)
        try c.encode(totalEpisodes, forKey: .totalEpisodes)
        try c.encodeIfPresent(collection, forKey: .collection)
        try c.encode(infobox, forKey: .infobox)
        try c.encode(heat, forKey: .heat)
        var rc = c.nestedContainer(keyedBy: RatingKeys.self, forKey: .rating)
        try rc.encode(rank, forKey: .rank)
        try rc.encode(ratingScore, forKey: .score)
        try rc.encode(ratingTotal, forKey: .total)
    }
}

// MARK: - Infobox

/// Bangumi `/v0/subjects/{id}` 返回的 infobox 条目。
///
/// 原始 `value` 可以是纯字符串，也可以是 `[{"v": "..."}]` 数组；本类型统一
/// 拍平成一个字符串（数组用「、」连接），编码时也按字符串写出。
public struct BangumiInfoboxEntry: Hashable, Sendable, Codable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    private struct ValueItem: Decodable {
        let v: String
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        if let str = try? c.decode(String.self, forKey: .value) {
            self.value = str
        } else if let items = try? c.decode([ValueItem].self, forKey: .value) {
            self.value = items.map(\.v).joined(separator: "、")
        } else {
            self.value = ""
        }
    }
}

// MARK: - Collection

/// `/v0/subjects/{id}` 的收藏分布。
public struct BangumiCollection: Hashable, Sendable, Codable {
    public let wish: Int
    public let collect: Int
    public let doing: Int
    public let onHold: Int
    public let dropped: Int

    public init(wish: Int = 0, collect: Int = 0, doing: Int = 0, onHold: Int = 0, dropped: Int = 0) {
        self.wish = wish
        self.collect = collect
        self.doing = doing
        self.onHold = onHold
        self.dropped = dropped
    }

    private enum CodingKeys: String, CodingKey {
        case wish
        case collect
        case doing
        case onHold = "on_hold"
        case dropped
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.wish = (try? c.decode(Int.self, forKey: .wish)) ?? 0
        self.collect = (try? c.decode(Int.self, forKey: .collect)) ?? 0
        self.doing = (try? c.decode(Int.self, forKey: .doing)) ?? 0
        self.onHold = (try? c.decode(Int.self, forKey: .onHold)) ?? 0
        self.dropped = (try? c.decode(Int.self, forKey: .dropped)) ?? 0
    }

    /// 收藏总人数 —— 详情页当「热度」用。
    public var total: Int {
        wish + collect + doing + onHold + dropped
    }
}
