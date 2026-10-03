import Foundation
import Testing
@testable import CezzuKit

@Suite("RuleVideoFilter")
struct RuleVideoFilterTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    /// 空 pattern 必须是恒等变换 —— 84 条既有规则都没有这个字段，行为不能变。
    @Test("empty pattern passes every url through unchanged")
    func emptyPatternIsIdentity() {
        let filter = RuleVideoFilter(pattern: "")
        let u = url("https://cdn.example.com/a/index.m3u8")
        #expect(filter.accept(u) == u)
    }

    /// 只留下命中的那一路，其余丢弃。
    @Test("keeps matching urls and drops the rest")
    func filtersByPattern() {
        let filter = RuleVideoFilter(pattern: #"(vdownload|abre-videos).*1080.*\.(m3u8|mp4)"#)
        #expect(filter.accept(url("https://vdownload.example/x/1080/index.m3u8")) != nil)
        #expect(filter.accept(url("https://vdownload.example/x/720/index.m3u8")) == nil)
        #expect(filter.accept(url("https://ads.example/preroll.mp4")) == nil)
    }

    /// 站点常把真地址塞在 `?url=` 后面，命名组 `v` 负责把它抽出来。
    @Test("named group v rewrites the url to the captured inner address")
    func namedGroupRewritesURL() {
        let filter = RuleVideoFilter(pattern: #".+\?url=(?<v>.+)"#)
        let out = filter.accept(url("https://player.example/go?url=https://cdn.example/real.m3u8"))
        #expect(out?.absoluteString == "https://cdn.example/real.m3u8")
    }

    /// `?url=` 后面的地址通常是百分号编码过的。
    @Test("percent-decodes the captured inner address")
    func namedGroupDecodesPercentEncoding() {
        let filter = RuleVideoFilter(pattern: #".+\?url=(?<v>.+)"#)
        let out = filter.accept(
            url("https://player.example/go?url=https%3A%2F%2Fcdn.example%2Freal.m3u8")
        )
        #expect(out?.absoluteString == "https://cdn.example/real.m3u8")
    }

    /// 没有 `v` 组时保留原地址，只做过滤。
    @Test("keeps the original url when the pattern has no v group")
    func matchWithoutNamedGroupKeepsURL() {
        let filter = RuleVideoFilter(pattern: #"\.m3u8"#)
        let u = url("https://cdn.example/a.m3u8?token=1")
        #expect(filter.accept(u) == u)
    }

    /// 一条写错的正则不该让整个源播不了 —— 退回全放行。
    @Test("an invalid pattern degrades to passing everything through")
    func invalidPatternDegradesToIdentity() {
        let filter = RuleVideoFilter(pattern: "([unclosed")
        let u = url("https://cdn.example/a.m3u8")
        #expect(filter.accept(u) == u)
    }

    /// 规则没写这个字段时同样是恒等变换。
    @Test("a rule without the field behaves like an empty pattern")
    func ruleWithoutPatternIsIdentity() throws {
        let rule = try JSONDecoder().decode(
            CezzuRule.self, from: Data(CezzuRuleFixtures.minimal.utf8)
        )
        let u = url("https://cdn.example/a.m3u8")
        #expect(RuleVideoFilter(rule: rule).accept(u) == u)
    }
}

@Suite("RuleCookies")
struct RuleCookiesTests {

    @Test("parses a semicolon separated cookie string")
    func parsesPairs() {
        let parsed = RuleCookies.parse("quality=1080; lang=zh")
        #expect(parsed.map(\.name) == ["quality", "lang"])
        #expect(parsed.map(\.value) == ["1080", "zh"])
    }

    /// 值里带 `=` 的（base64 之类）只按第一个 `=` 切。
    @Test("splits on the first equals only")
    func splitsOnFirstEquals() {
        let parsed = RuleCookies.parse("token=abc=def==")
        #expect(parsed.count == 1)
        #expect(parsed[0].value == "abc=def==")
    }

    /// 空片段、缺 `=`、名字为空的片段一律跳过，不能崩也不能产出脏 cookie。
    @Test("skips malformed pieces")
    func skipsMalformed() {
        let parsed = RuleCookies.parse(";; broken ; =novalue ; ok=1 ;")
        #expect(parsed.map(\.name) == ["ok"])
    }

    @Test("binds cookies to the play page host")
    func bindsToHost() throws {
        let cookies = RuleCookies.cookies(
            from: "quality=1080", for: URL(string: "https://hanime1.me/watch?v=1")!
        )
        #expect(cookies.count == 1)
        #expect(cookies[0].domain.contains("hanime1.me"))
        #expect(cookies[0].name == "quality")
        #expect(cookies[0].path == "/")
    }

    /// 取不到 host 就别产出 cookie —— HTTPCookie 缺 domain 会直接构造失败。
    @Test("produces nothing for a url without a host")
    func noHostNoCookies() {
        let cookies = RuleCookies.cookies(from: "a=1", for: URL(string: "file:///tmp/x.html")!)
        #expect(cookies.isEmpty)
    }
}

enum CezzuRuleFixtures {
    /// 不含 api 9 字段的最小规则，用来确认新字段缺失时的默认行为。
    static let minimal = """
        {
            "api": "1",
            "type": "anime",
            "name": "minimal",
            "version": "1.0",
            "muliSources": true,
            "useWebview": true,
            "useNativePlayer": true,
            "userAgent": "",
            "baseURL": "https://example.com/",
            "searchURL": "https://example.com/s?q=@keyword",
            "searchList": "//li",
            "searchName": "//a",
            "searchResult": "//a",
            "chapterRoads": "//ul",
            "chapterResult": "//li/a"
        }
        """
}
