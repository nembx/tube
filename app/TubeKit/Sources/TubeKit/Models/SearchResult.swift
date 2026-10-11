import Foundation

/// 单个搜索结果（一部番剧）。由规则引擎从一个站点的搜索结果页里解析出来。
public struct SearchResult: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var detailURL: URL
    public var ruleName: String

    public init(id: UUID = UUID(), title: String, detailURL: URL, ruleName: String) {
        self.id = id
        self.title = title
        self.detailURL = detailURL
        self.ruleName = ruleName
    }
}

/// 一组来自同一规则的搜索结果（用于按规则分组的 UI）。
public struct RuleResultsGroup: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable {
        case running
        case done
        case failed(message: String)
    }

    public var id: String { ruleName }
    public var ruleName: String
    public var results: [SearchResult]
    public var status: Status

    public init(ruleName: String, results: [SearchResult], status: Status) {
        self.ruleName = ruleName
        self.results = results
        self.status = status
    }
}
