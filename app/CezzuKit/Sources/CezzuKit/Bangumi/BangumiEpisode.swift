import Foundation

/// Bangumi 条目下的一集（`/v0/episodes`）。
public struct BangumiEpisode: Hashable, Sendable, Identifiable, Decodable {
    public let id: Int
    /// 正片集数。SP / OP 这类非正片在 bgm 上是另一个 type，这里只会拿到正片。
    public let ep: Double
    /// 排序号。少数条目 `ep` 缺失，只有 `sort` 有值。
    public let sort: Double
    public let name: String
    public let nameCn: String
    public let airDate: String
    /// 形如 `00:23:40`，bgm 没填时是空串。
    public let duration: String
    /// 单集简介。bgm 单集页顶部那段就是它。
    public let desc: String
    /// bgm 上这一集的吐槽数，用来在 tab 上给个数字。
    public let commentCount: Int

    public var displayTitle: String {
        nameCn.isEmpty ? name : nameCn
    }

    public init(
        id: Int,
        ep: Double,
        sort: Double,
        name: String,
        nameCn: String,
        airDate: String,
        duration: String = "",
        desc: String = "",
        commentCount: Int
    ) {
        self.id = id
        self.ep = ep
        self.sort = sort
        self.name = name
        self.nameCn = nameCn
        self.airDate = airDate
        self.duration = duration
        self.desc = desc
        self.commentCount = commentCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, ep, sort, name, comment, duration, desc
        case nameCn = "name_cn"
        case airDate = "airdate"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.sort = (try? c.decode(Double.self, forKey: .sort)) ?? 0
        self.ep = (try? c.decode(Double.self, forKey: .ep)) ?? self.sort
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.nameCn = (try? c.decode(String.self, forKey: .nameCn)) ?? ""
        self.airDate = (try? c.decode(String.self, forKey: .airDate)) ?? ""
        self.duration = (try? c.decode(String.self, forKey: .duration)) ?? ""
        self.desc = (try? c.decode(String.self, forKey: .desc)) ?? ""
        self.commentCount = (try? c.decode(Int.self, forKey: .comment)) ?? 0
    }
}

extension BangumiEpisode {
    /// 集号 + 标题，形如 `ep.1 温泉与誓言`。
    public var displayHeadline: String {
        let number = Int(ep > 0 ? ep : sort)
        let title = displayTitle
        return title.isEmpty ? "ep.\(number)" : "ep.\(number) \(title)"
    }

    /// 把播放器里的第 N 集（0 起）对到 bgm 的某一集。
    ///
    /// 播放源来自第三方站点，集号不保证和 bgm 对得上：先按 `ep` 号找，再按 `sort` 找，
    /// 都落空才退回按位置取 —— 位置是最后的兜底，站点少收录一集就会整体错位。
    public static func match(episodeIndex: Int, in episodes: [BangumiEpisode]) -> BangumiEpisode? {
        guard episodeIndex >= 0 else { return nil }
        let number = Double(episodeIndex + 1)
        if let byEp = episodes.first(where: { $0.ep == number }) { return byEp }
        if let bySort = episodes.first(where: { $0.sort == number }) { return bySort }
        return episodes.indices.contains(episodeIndex) ? episodes[episodeIndex] : nil
    }
}

/// bgm.tv 单集页（`/ep/{id}`）里的一条吐槽。
public struct BangumiEpisodeComment: Hashable, Sendable, Identifiable {
    public let id: String
    /// 楼层号，形如 `#12`。
    public let floor: String
    public let authorName: String
    public let avatarURL: URL?
    public let publishedAt: String
    public let body: String
    /// 楼里贴的图。bgm 的表情（`img.smile`）不算，只收用户上传的图片。
    public let imageURLs: [URL]
    /// 楼中楼。子楼自己不再有子楼，所以这一层就够。
    public let replies: [BangumiEpisodeComment]

    public init(
        id: String,
        floor: String,
        authorName: String,
        avatarURL: URL?,
        publishedAt: String,
        body: String,
        imageURLs: [URL] = [],
        replies: [BangumiEpisodeComment] = []
    ) {
        self.id = id
        self.floor = floor
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.publishedAt = publishedAt
        self.body = body
        self.imageURLs = imageURLs
        self.replies = replies
    }
}
