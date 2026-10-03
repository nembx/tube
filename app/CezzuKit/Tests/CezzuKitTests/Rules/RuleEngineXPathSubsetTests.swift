import Foundation
import Testing
@testable import CezzuKit

@Suite("XPath subset on Kanna")
struct RuleEngineXPathSubsetTests {

    @Test("class predicate matches")
    func classPredicate() throws {
        let html = """
        <html><body>
            <div class='vod-detail style-detail cor4 search-list'>
                <div><div><a href='/play/1'><h3>Foo</h3></a></div></div>
            </div>
        </body></html>
        """
        let doc = try KannaXPathHTMLDocument(html: html)
        let nodes = doc.xpath("//div[@class='vod-detail style-detail cor4 search-list']")
        #expect(nodes.count == 1)
    }

    @Test("nested xpath relative to context")
    func nestedXPath() throws {
        let html = """
        <html><body>
            <div class='item'>
                <a href='/x'><h3>Title</h3></a>
            </div>
        </body></html>
        """
        let doc = try KannaXPathHTMLDocument(html: html)
        let items = doc.xpath("//div[@class='item']")
        #expect(items.count == 1)
        let titles = items[0].xpath("//a/h3")
        #expect(titles.count == 1)
        #expect(titles[0].text == "Title")
    }

    @Test("href attribute extraction")
    func hrefAttribute() throws {
        let html = "<html><body><a href='/play/123'>Click</a></body></html>"
        let doc = try KannaXPathHTMLDocument(html: html)
        let anchors = doc.xpath("//a")
        #expect(anchors.first?["href"] == "/play/123")
    }

    @Test("LiveRuleEngine.parseSearchResults integrates")
    func parseSearchResultsIntegration() throws {
        let html = """
        <html><body>
            <div class='vod-detail style-detail cor4 search-list'>
                <div><div><a href='/play/abc'><h3>孤独摇滚</h3></a></div></div>
            </div>
            <div class='vod-detail style-detail cor4 search-list'>
                <div><div><a href='/play/def'><h3>鬼灭之刃</h3></a></div></div>
            </div>
        </body></html>
        """
        let rule = CezzuRule(
            api: "1",
            type: "anime",
            name: "demo",
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//div[@class='vod-detail style-detail cor4 search-list']",
            searchName: "//div/div/a/h3",
            searchResult: "//div/div/a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        let engine = LiveRuleEngine()
        let results = try engine.parseSearchResults(html: html, rule: rule)
        #expect(results.count == 2)
        #expect(results[0].title == "孤独摇滚")
        #expect(results[0].detailURL.absoluteString == "https://example.com/play/abc")
        #expect(results[1].title == "鬼灭之刃")
    }

    @Test("LiveRuleEngine.parseEpisodes handles multi-road")
    func parseEpisodesMultiRoad() throws {
        let html = """
        <html><body>
            <ul class='ep-list'>
                <li><a href='/p/1-1'>第 1 集</a></li>
                <li><a href='/p/1-2'>第 2 集</a></li>
            </ul>
            <ul class='ep-list'>
                <li><a href='/p/2-1'>第 1 集</a></li>
                <li><a href='/p/2-2'>第 2 集</a></li>
            </ul>
        </body></html>
        """
        let rule = CezzuRule(
            api: "1",
            type: "anime",
            name: "demo",
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//div",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul[@class='ep-list']",
            chapterResult: "//li/a"
        )
        let engine = LiveRuleEngine()
        let roads = try engine.parseEpisodes(
            html: html, rule: rule, baseURL: URL(string: "https://example.com/detail/1")!
        )
        #expect(roads.count == 2)
        #expect(roads[0].episodes.count == 2)
        #expect(roads[1].episodes.count == 2)
        #expect(roads[0].episodes[0].url.absoluteString == "https://example.com/p/1-1")
        #expect(roads[1].episodes[0].url.absoluteString == "https://example.com/p/2-1")
    }
}
