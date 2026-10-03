import Foundation
import SwiftData

/// 一条搜索历史。`keyword` 唯一，重复搜索会原地更新 `lastUsedAt` 让它上浮。
@Model
public final class SearchHistoryEntry {
    @Attribute(.unique) public var keyword: String
    public var lastUsedAt: Date

    public init(keyword: String, lastUsedAt: Date = .now) {
        self.keyword = keyword
        self.lastUsedAt = lastUsedAt
    }
}
