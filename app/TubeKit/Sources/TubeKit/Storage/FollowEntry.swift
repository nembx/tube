import Foundation
import SwiftData

/// 一条追番记录。按 Bangumi subject id 优先去重；没有 subject id 时回落到显示名。
@Model
public final class FollowEntry {
    @Attribute(.unique) public var key: String
    public var subjectID: Int
    public var name: String
    public var nameCn: String
    public var summary: String
    public var airDate: String
    public var rank: Int
    public var ratingScore: Double
    public var ratingTotal: Int
    public var eps: Int
    public var platform: String
    public var episodeDuration: String
    public var imageLarge: String
    public var imageCommon: String
    public var imageMedium: String
    public var imageSmall: String
    public var imageGrid: String
    public var updatedAt: Date

    public init(item: BangumiItem, updatedAt: Date = .now) {
        self.key = FollowEntry.makeKey(for: item)
        self.subjectID = item.id
        self.name = item.name
        self.nameCn = item.nameCn
        self.summary = item.summary
        self.airDate = item.airDate
        self.rank = item.rank
        self.ratingScore = item.ratingScore
        self.ratingTotal = item.ratingTotal
        self.eps = item.eps
        self.platform = item.platform
        self.episodeDuration = item.episodeDuration
        self.imageLarge = item.images.large
        self.imageCommon = item.images.common
        self.imageMedium = item.images.medium
        self.imageSmall = item.images.small
        self.imageGrid = item.images.grid
        self.updatedAt = updatedAt
    }

    public var item: BangumiItem {
        BangumiItem(
            id: subjectID,
            name: name,
            nameCn: nameCn,
            summary: summary,
            airDate: airDate,
            rank: rank,
            ratingScore: ratingScore,
            images: BangumiImages(
                large: imageLarge,
                common: imageCommon,
                medium: imageMedium,
                small: imageSmall,
                grid: imageGrid
            ),
            tags: [],
            ratingTotal: ratingTotal,
            eps: eps,
            platform: platform,
            episodeDuration: episodeDuration
        )
    }

    public static func makeKey(for item: BangumiItem) -> String {
        if item.id > 0 {
            return "subject:\(item.id)"
        }
        return "name:\(item.displayName)"
    }
}
