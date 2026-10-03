import Foundation

public struct HistoryResumeHint: Hashable, Sendable {
    public let bangumiTitle: String
    public let coverURLString: String?
    public let detailURL: URL
    public let ruleName: String
    public let episodeIndex: Int
    public let episodeTitle: String
    public let positionMs: Int
    /// 这条历史对应的 bangumi 条目号。老历史没存过，为 nil —— 详情页会按标题去找回来。
    public let subjectID: Int?

    public init(
        bangumiTitle: String,
        coverURLString: String?,
        detailURL: URL,
        ruleName: String,
        episodeIndex: Int,
        episodeTitle: String,
        positionMs: Int,
        subjectID: Int? = nil
    ) {
        self.bangumiTitle = bangumiTitle
        self.coverURLString = coverURLString
        self.detailURL = detailURL
        self.ruleName = ruleName
        self.episodeIndex = episodeIndex
        self.episodeTitle = episodeTitle
        self.positionMs = positionMs
        self.subjectID = subjectID
    }

    public var item: BangumiItem {
        let cover = coverURLString ?? ""
        return BangumiItem(
            id: subjectID ?? 0,
            name: bangumiTitle,
            nameCn: bangumiTitle,
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: BangumiImages(
                large: cover,
                common: cover,
                medium: cover,
                small: cover,
                grid: cover
            ),
            tags: []
        )
    }
}

/// 整个 App 用的 deep-link `Route` 枚举。
public enum Route: Hashable, Sendable {
    case home
    case follow
    case search
    case detail(BangumiItem)
    case historyDetail(HistoryResumeHint)
    /// 首页分区「查看全部」；`tag` 为空表示热门番组。
    case tagSection(tag: String)
    case episodes(detail: AnimeDetail)
    case player(PlaybackRequest)
    case ruleManager
    case ruleSources
    case settings

    /// 这个目的地是不是恒定深色底。dock / 导航栏的前景色要按栈顶页面的明暗算 ——
    /// 从首页 push 进来的「查看全部」「详情」是跟随系统的，dock 不能还停在深色。
    public var prefersDarkChrome: Bool {
        switch self {
        case .home, .search, .player:
            return true
        case .follow, .detail, .historyDetail, .tagSection, .episodes,
             .ruleManager, .ruleSources, .settings:
            return false
        }
    }
}
