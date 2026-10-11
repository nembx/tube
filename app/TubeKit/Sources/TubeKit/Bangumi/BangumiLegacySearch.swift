import Foundation

/// `GET /search/subject/{keywords}` —— bgm 已 deprecated 的全文搜索接口。
///
/// 保留它是因为 `/v0/search/subjects` 对匿名客户端会静默丢掉一部分条目
/// （bgm 自己的 OpenAPI：「无权限情况下忽略此选项，不会返回 NSFW 条目」），
/// 而这个老接口不受该策略约束，是不登录时唯一能召回它们的入口。
///
/// 它的响应形态和 v0 差异很大，不能直接复用 `BangumiItem` 的解码器：
///   - `rank` 在顶层，v0 在 `rating.rank` 里
///   - 出错时 HTTP 仍是 200，body 变成 `{"request":..., "code":404, "error":...}`
///   - `list` 在有 `results` 的情况下也可能是 `null`
///   - 图片是 `http://`，iOS 的 ATS 会直接拦掉
enum BangumiLegacySearch {
    /// 服务端实测的单页上限：传 100 也只回 24 条左右。
    static let maxPageSize = 25

    /// 关键词是拼进 URL **path** 的，不是 query。
    /// `/`、`!`、`%` 这类字符即使做了百分号编码，服务端也会直接返回 404 错误对象
    /// （实测 `Fate/Zero`、`K-ON!` 都会挂），所以先把它们换成空格再编码。
    static func sanitizeKeyword(_ keyword: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?#%&+!！？。，、·:：;；\"'“”‘’()（）[]【】{}<>《》|~^`$@*=")
        let replaced = String(
            keyword.unicodeScalars.map { illegal.contains($0) ? " " : Character($0) }
        )
        return replaced.split(separator: " ").joined(separator: " ")
    }

    /// 把 `http://lain.bgm.tv/...` 提升到 https —— 老接口只给 http，ATS 会拦。
    static func upgradeToHTTPS(_ url: String) -> String {
        guard url.hasPrefix("http://") else { return url }
        return "https://" + url.dropFirst("http://".count)
    }
}

// MARK: - Response

/// 老接口的成功响应。`list` 可能为 `null`（`results` 非 0 时也会发生）。
struct BangumiLegacySearchResponse: Decodable {
    let results: Int
    let list: [BangumiLegacySubject]

    private enum CodingKeys: String, CodingKey {
        case results
        case list
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.results = (try? c.decode(Int.self, forKey: .results)) ?? 0
        self.list = (try? c.decodeIfPresent([BangumiLegacySubject].self, forKey: .list)) ?? []
    }
}

/// 老接口在参数非法 / 无结果时返回的错误对象 —— HTTP 状态码仍然是 200。
struct BangumiLegacyErrorEnvelope: Decodable {
    let code: Int
    let error: String?
}

// MARK: - Subject

struct BangumiLegacySubject: Decodable {
    let id: Int
    let name: String
    let nameCn: String
    let summary: String
    let airDate: String
    let eps: Int
    let rank: Int
    let ratingScore: Double
    let ratingTotal: Int
    let images: BangumiImages
    let collection: BangumiCollection?

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, eps, rank, rating, images, collection
        case nameCn = "name_cn"
        case airDate = "air_date"
        case epsCount = "eps_count"
    }

    private enum RatingKeys: String, CodingKey {
        case score, total
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let cn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        self.nameCn = cn.isEmpty ? self.name : cn
        self.summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        self.airDate = (try? c.decode(String.self, forKey: .airDate)) ?? ""

        // `eps` 在部分条目上是 0，`eps_count` 才是真正的话数。
        let eps = (try? c.decode(Int.self, forKey: .eps)) ?? 0
        let epsCount = (try? c.decode(Int.self, forKey: .epsCount)) ?? 0
        self.eps = eps > 0 ? eps : epsCount

        // rank 在顶层，不在 rating 里。
        self.rank = (try? c.decode(Int.self, forKey: .rank)) ?? 0
        if let rc = try? c.nestedContainer(keyedBy: RatingKeys.self, forKey: .rating) {
            self.ratingScore = (try? rc.decode(Double.self, forKey: .score)) ?? 0
            self.ratingTotal = (try? rc.decode(Int.self, forKey: .total)) ?? 0
        } else {
            self.ratingScore = 0
            self.ratingTotal = 0
        }

        if let raw = try? c.decode(BangumiImages.self, forKey: .images) {
            self.images = BangumiImages(
                large: BangumiLegacySearch.upgradeToHTTPS(raw.large),
                common: BangumiLegacySearch.upgradeToHTTPS(raw.common),
                medium: BangumiLegacySearch.upgradeToHTTPS(raw.medium),
                small: BangumiLegacySearch.upgradeToHTTPS(raw.small),
                grid: BangumiLegacySearch.upgradeToHTTPS(raw.grid)
            )
        } else {
            self.images = .empty
        }

        self.collection = try? c.decode(BangumiCollection.self, forKey: .collection)
    }

    /// 老接口没有 tags / infobox / meta_tags / platform，这些字段留空。
    /// `DetailViewModel` 对空值本来就有降级路径（`loadSubjectIfNeeded` 只做增量补齐）。
    func toBangumiItem() -> BangumiItem {
        BangumiItem(
            id: id,
            name: name,
            nameCn: nameCn,
            summary: summary,
            airDate: airDate,
            rank: rank,
            ratingScore: ratingScore,
            images: images,
            tags: [],
            ratingTotal: ratingTotal,
            eps: eps,
            totalEpisodes: eps,
            collection: collection
        )
    }
}
