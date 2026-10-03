import Foundation
import SwiftData

/// 一条观看历史。每部番剧一条；进度更新时原地更新。
@Model
public final class WatchHistoryEntry {
    @Attribute(.unique) public var detailURLString: String
    public var bangumiTitle: String
    public var coverURLString: String?
    public var ruleName: String
    public var lastEpisodeIndex: Int
    public var lastEpisodeTitle: String
    public var lastPositionMs: Int
    public var updatedAt: Date
    /// bangumi 条目号。没有它的话，从历史进详情页只剩标题和一张播放截图 ——
    /// 简介、封面、评分、分集评论全都拿不到。老数据没有这个字段，所以是可选。
    public var subjectID: Int?

    public init(
        detailURLString: String,
        bangumiTitle: String,
        coverURLString: String?,
        ruleName: String,
        lastEpisodeIndex: Int,
        lastEpisodeTitle: String,
        lastPositionMs: Int,
        subjectID: Int? = nil,
        updatedAt: Date = .now
    ) {
        self.detailURLString = detailURLString
        self.bangumiTitle = bangumiTitle
        self.coverURLString = coverURLString
        self.ruleName = ruleName
        self.lastEpisodeIndex = lastEpisodeIndex
        self.lastEpisodeTitle = lastEpisodeTitle
        self.lastPositionMs = lastPositionMs
        self.subjectID = subjectID
        self.updatedAt = updatedAt
    }
}
