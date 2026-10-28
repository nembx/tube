import Foundation
import Testing
@testable import TubeKit

@Suite("Kazumi rule compatibility")
struct KazumiCompatibilityTests {
    private func seed(_ name: String) throws -> TubeRule {
        let url = try #require(Bundle.tubeKit.url(forResource: "SeedRules/\(name)", withExtension: "json"))
        return try JSONDecoder().decode(TubeRule.self, from: Data(contentsOf: url))
    }

    @Test("API search ids resolve to the configured HTML detail page", arguments: [
        ("LMM", "https://www.lmm85.com/index.php/vod/detail/id/42.html"),
        ("dalvdm", "https://www.sbdl.cc/index.php/vod/detail/id/42.html"),
        ("moonci", "https://www.moonci.com/anime/42.html"),
        ("mgnacg", "https://www.mgnacg.com/media/42"),
        ("mutefun", "https://www.mutedm.com/voddetail/42"),
    ])
    func hybridSearch(_ name: String, _ expectedURL: String) throws {
        let rule = try seed(name)
        let config = try #require(rule.searchApiConfig)
        // 与 MacCMS suggest 响应相同：id 为数字，详情地址不一定带 .html。
        let results = try ApiRuleEngine.parseSearch(
            data: Data(#"{"list":[{"id":42,"name":"测试番剧"}]}"#.utf8),
            config: config, ruleName: name, chapterMode: rule.chapterMode, baseURL: rule.baseURL
        )
        #expect(results.first?.detailURL.absoluteString == expectedURL)
    }

    @Test("new seeds execute API search through chapter parsing", arguments: ["LMM", "TvTFun", "xfdmnext"])
    func newSeedPipeline(_ name: String) async throws {
        let rule = try seed(name)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KazumiFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let engine = LiveRuleEngine(httpClient: HTTPClient(session: session))
        let results = try await engine.search("测试", with: rule)
        let result = try #require(results.first)
        #expect(result.title == "测试番剧")
        let roads = try await engine.fetchEpisodes(detailURL: result.detailURL, with: rule)
        let episode = try #require(roads.first?.episodes.first)
        #expect(episode.title == "第1集")
        let expected = [
            "LMM": "https://www.lmm85.com/index.php/vod/play/id/42/sid/1/nid/1.html",
            "TvTFun": "https://www.tvtfun.net/watch/demo/1",
            "xfdmnext": "https://next.xifanacg.com/anime/42/play/ep-1",
        ]
        #expect(episode.url.absoluteString == expected[name])
        if name == "xfdmnext" { #expect(roads.count == 2) }
    }

    @Test("all active rules and their API configs match the bundled catalog")
    func catalogIntegrity() throws {
        let loader = SeededRuleLoader()
        let catalog = try loader.loadSeedCatalog()
        let rules = try loader.loadSeedRules()
        #expect(Set(catalog.map(\.name)) == Set(rules.map(\.name)))
        for entry in catalog {
            let rule = try seed(entry.name)
            #expect(rule.version == entry.version)
            if let search = rule.searchApiConfig { try ApiRuleEngine.validateSearchConfig(search) }
            if let chapters = rule.chapterApiConfig { try ApiRuleEngine.validateChapterConfig(chapters) }
        }
    }
}

/// 只接受规则实际构造出的 URL；映射错误会直接返回 404。
private final class KazumiFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body: String?
        switch (url.host, url.path) {
        case ("www.lmm85.com", "/index.php/ajax/suggest"):
            body = #"{"list":[{"id":42,"name":"测试番剧"}]}"#
        case ("www.lmm85.com", "/index.php/vod/detail/id/42.html"):
            body = """
            <html><body><div class='module-player-list'>
            <a href='/index.php/vod/play/id/42/sid/1/nid/1.html'>第1集</a>
            </div></body></html>
            """
        case ("www.tvtfun.net", "/api/client/anime"):
            body = #"{"data":{"items":[{"slug":"demo","name":"测试番剧"}]}}"#
        case ("www.tvtfun.net", "/watch/demo/1"):
            body = """
            <html><body><ol class='tvt-watch-episodes grid'>
            <li><a href='/watch/demo/1'>第1集</a></li>
            </ol></body></html>
            """
        case ("api.xifanacg.com", "/rest/v1/rpc/search_animes"):
            body = #"[{"id":"42","title":"测试番剧"}]"#
        case ("api.xifanacg.com", "/rest/v1/rpc/get_anime_detail"):
            body = #"""
            {"sources":[
              {"name":"线路1","episodes":[{"id":"ep-1","title":"第1集"}]},
              {"name":"线路2","episodes":[{"id":"ep-2","title":"第1集"}]}
            ]}
            """#
        default: body = nil
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
