import Foundation
import Testing
@testable import CezzuKit

@Suite("LiveRuleEngine captcha detection")
struct RuleEngineCaptchaDetectionTests {

    private func makeRule(anti: AntiCrawlerConfig?) -> CezzuRule {
        CezzuRule(
            api: "6",
            type: "anime",
            name: "giri",
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//div[@class='search-list']",
            searchName: ".//h3",
            searchResult: ".//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a",
            antiCrawlerConfig: anti
        )
    }

    private let captchaHTML = """
        <html><body>
            <form id='captcha-form'>
                <img id='captcha-image' src='/captcha.png'/>
                <input id='captcha-input' name='code'/>
                <button id='captcha-submit'>提交</button>
            </form>
        </body></html>
        """

    private let normalHTML = """
        <html><body>
            <div class='search-list'>
                <a href='/play/1'><h3>孤独摇滚</h3></a>
            </div>
        </body></html>
        """

    @Test("captcha page matching configured xpath throws captchaRequired")
    func captchaThrows() throws {
        let cfg = AntiCrawlerConfig(
            enabled: true,
            captchaType: .imageCaptcha,
            captchaImage: "//img[@id='captcha-image']",
            captchaInput: "//input[@id='captcha-input']",
            captchaButton: "//button[@id='captcha-submit']"
        )
        let engine = LiveRuleEngine()
        #expect(throws: RuleEngineError.self) {
            try engine.parseSearchResults(html: captchaHTML, rule: makeRule(anti: cfg))
        }
    }

    @Test("disabled antiCrawlerConfig skips detection")
    func disabledSkips() throws {
        let cfg = AntiCrawlerConfig(
            enabled: false,
            captchaType: .imageCaptcha,
            captchaImage: "//img[@id='captcha-image']",
            captchaInput: "//input[@id='captcha-input']",
            captchaButton: "//button[@id='captcha-submit']"
        )
        let engine = LiveRuleEngine()
        let results = try engine.parseSearchResults(html: captchaHTML, rule: makeRule(anti: cfg))
        #expect(results.isEmpty)
    }

    @Test("missing antiCrawlerConfig does not throw")
    func missingConfig() throws {
        let engine = LiveRuleEngine()
        let results = try engine.parseSearchResults(html: normalHTML, rule: makeRule(anti: nil))
        #expect(results.count == 1)
        #expect(results[0].title == "孤独摇滚")
    }

    @Test("enabled config without xpath matches returns results normally")
    func enabledButNoMatch() throws {
        let cfg = AntiCrawlerConfig(
            enabled: true,
            captchaType: .imageCaptcha,
            captchaImage: "//img[@id='captcha-image']",
            captchaInput: "//input[@id='captcha-input']",
            captchaButton: "//button[@id='captcha-submit']"
        )
        let engine = LiveRuleEngine()
        let results = try engine.parseSearchResults(html: normalHTML, rule: makeRule(anti: cfg))
        #expect(results.count == 1)
    }
}
