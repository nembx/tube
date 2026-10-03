import Foundation

/// Bangumi 搜索排序方式。
public enum BangumiSearchSort: String, CaseIterable, Hashable, Sendable, Codable {
    case match
    case heat
    case rank
    case score

    public var title: String {
        switch self {
        case .match:
            return "匹配度"
        case .heat:
            return "热度"
        case .rank:
            return "排名"
        case .score:
            return "评分"
        }
    }
}
