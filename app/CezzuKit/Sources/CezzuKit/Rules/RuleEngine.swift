import Foundation

/// 规则引擎对外暴露的两条高层 API。一条规则一次输入，一组结果一次输出。
public protocol RuleEngine: Sendable {
    /// 用一条规则搜索关键字，返回搜索结果列表。
    func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult]

    /// 给定一个详情页 URL 与对应规则，抓出多线路的剧集列表。
    func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad]
}
