import Foundation

/// Bangumi.tv subject 的封面图集合。
public struct BangumiImages: Hashable, Sendable, Codable {
    public let large: String
    public let common: String
    public let medium: String
    public let small: String
    public let grid: String

    public init(large: String, common: String, medium: String, small: String, grid: String) {
        self.large = large
        self.common = common
        self.medium = medium
        self.small = small
        self.grid = grid
    }

    /// 兜底空对象，给缺失 images 字段的条目用。
    public static let empty = BangumiImages(
        large: "", common: "", medium: "", small: "", grid: ""
    )

    /// 给详情页等大尺寸 UI 用的最佳图片。
    public var best: String {
        for candidate in [large, common, medium, grid, small] {
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }

    /// 给首页 / 搜索宫格用的封面尺寸，避免列表直接拉原图。
    public var listBest: String {
        for candidate in [common, medium, small, grid, large] {
            if !candidate.isEmpty { return candidate }
        }
        return ""
    }
}
