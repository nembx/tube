import Foundation
import Testing
@testable import TubeKit

@Suite("BangumiImageMirrorSettings")
struct BangumiImageMirrorSettingsTests {

    private let cover = URL(string: "https://lain.bgm.tv/pic/cover/l/ab/cd/123.jpg")!

    // MARK: - 默认（wsrv.nl，Kazumi 同款）

    @Test("default mirror routes covers through wsrv.nl without a scheme")
    func defaultMirror() throws {
        let mirrored = try #require(
            BangumiImageMirrorSettings.mirroredURL(for: cover, mirrorPrefix: "https://wsrv.nl")
        )
        let items = URLComponents(url: mirrored, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(mirrored.host == "wsrv.nl")
        #expect(items.first { $0.name == "url" }?.value == "lain.bgm.tv/pic/cover/l/ab/cd/123.jpg")
        #expect(items.first { $0.name == "n" } == nil)
    }

    @Test("default mirror keeps the query string and adds n=-1 for gifs")
    func defaultMirrorQueryAndGif() throws {
        let gif = URL(string: "https://lain.bgm.tv/pic/cover/l/a.gif?x=1")!
        let mirrored = try #require(
            BangumiImageMirrorSettings.mirroredURL(for: gif, mirrorPrefix: "https://wsrv.nl/")
        )
        let items = URLComponents(url: mirrored, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "url" }?.value == "lain.bgm.tv/pic/cover/l/a.gif?x=1")
        #expect(items.first { $0.name == "n" }?.value == "-1")
    }

    @Test("api.bgm.tv image endpoints are mirrored too")
    func apiImageEndpoints() throws {
        let image = URL(string: "https://api.bgm.tv/v0/subjects/123/image")!
        #expect(BangumiImageMirrorSettings.shouldMirror(image))
        let mirrored = try #require(
            BangumiImageMirrorSettings.mirroredURL(for: image, mirrorPrefix: "https://wsrv.nl")
        )
        let items = URLComponents(url: mirrored, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "url" }?.value == "api.bgm.tv/v0/subjects/123/image")

        // 非图片类接口不改写
        #expect(!BangumiImageMirrorSettings.shouldMirror(URL(string: "https://api.bgm.tv/v0/subjects/123")!))
        #expect(!BangumiImageMirrorSettings.shouldMirror(URL(string: "https://api.bgm.tv/v0/subjects/abc/image")!))
        #expect(!BangumiImageMirrorSettings.shouldMirror(URL(string: "https://api.bgm.tv/v0/episodes/1/image")!))
    }

    // MARK: - 前缀式

    @Test("prefix-style mirror keeps path and query")
    func prefixStyle() throws {
        let withQuery = URL(string: "https://lain.bgm.tv/pic/cover/l/123.jpg?x=1")!
        let mirrored = try #require(
            BangumiImageMirrorSettings.mirroredURL(for: withQuery, mirrorPrefix: "https://img.example.com/")
        )
        #expect(mirrored.absoluteString == "https://img.example.com/pic/cover/l/123.jpg?x=1")
    }

    @Test("candidates try the mirror first and the original second")
    func fallbackOrder() {
        let urls = BangumiImageMirrorSettings.candidateURLs(for: cover, mirrorPrefix: "https://img.example.com")
        #expect(urls.map(\.host) == ["img.example.com", "lain.bgm.tv"])
    }

    @Test("non-bgm hosts are never rewritten")
    func otherHostsUntouched() {
        let ddp = URL(string: "https://api.dandanplay.net/avatar/1.png")!
        #expect(BangumiImageMirrorSettings.mirroredURL(for: ddp, mirrorPrefix: "https://wsrv.nl") == nil)
        #expect(BangumiImageMirrorSettings.candidateURLs(for: ddp, mirrorPrefix: "https://wsrv.nl") == [ddp])
    }

    // MARK: - 配置

    @Test("off / direct disables the mirror")
    func disable() {
        #expect(BangumiImageMirrorSettings.sanitize("off") == "")
        #expect(BangumiImageMirrorSettings.sanitize(" direct ") == "")
        #expect(BangumiImageMirrorSettings.candidateURLs(for: cover, mirrorPrefix: "off") == [cover])
    }

    @Test("sanitize rejects junk and trims slashes")
    func sanitize() {
        #expect(BangumiImageMirrorSettings.sanitize("  https://img.example.com//  ") == "https://img.example.com")
        #expect(BangumiImageMirrorSettings.sanitize("img.example.com") == "")
        #expect(BangumiImageMirrorSettings.sanitize("ftp://img.example.com") == "")
        #expect(BangumiImageMirrorSettings.sanitize("") == "")
        #expect(BangumiImageMirrorSettings.sanitize("http://127.0.0.1:8080") == "http://127.0.0.1:8080")
    }

    @Test("settings default to wsrv.nl and can be disabled")
    func fromDefaults() {
        let suite = "BangumiImageMirrorSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(BangumiImageMirrorSettings.mirrorPrefix(from: defaults) == "https://wsrv.nl")
        defaults.set("off", forKey: BangumiImageMirrorSettings.mirrorKey)
        #expect(BangumiImageMirrorSettings.mirrorPrefix(from: defaults) == "")
        defaults.set("  https://img.example.com/ ", forKey: BangumiImageMirrorSettings.mirrorKey)
        #expect(BangumiImageMirrorSettings.mirrorPrefix(from: defaults) == "https://img.example.com")
    }
}
