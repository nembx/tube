import Foundation
import Testing
@testable import TubeKit

@Suite("BangumiSiteSettings")
struct BangumiSiteSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "BangumiSiteSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("official site derives the classic bgm domains")
    func officialDomains() {
        let site = BangumiSite.official
        #expect(site.apiDomain.absoluteString == "https://api.bgm.tv")
        #expect(site.webDomain.absoluteString == "https://bgm.tv")
        #expect(site.imageDomain.absoluteString == "https://lain.bgm.tv")
        #expect(site.nextDomain?.absoluteString == "https://next.bgm.tv")
        #expect(site.authorizeURL.absoluteString == "https://bgm.tv/oauth/authorize")
        #expect(site.tokenURL.absoluteString == "https://bgm.tv/oauth/access_token")
    }

    @Test("mirror site derives api/lain subdomains and has no next endpoint")
    func mirrorDomains() {
        let site = BangumiSite.mirrorLat
        #expect(site.apiDomain.absoluteString == "https://api.bangumi.lat")
        #expect(site.webDomain.absoluteString == "https://bangumi.lat")
        #expect(site.imageDomain.absoluteString == "https://lain.bangumi.lat")
        #expect(site.nextDomain == nil)
        // 授权页与换 token 固定官方：镜像网页有 Anubis 挑战，走镜像会 400。
        #expect(site.authorizeURL.absoluteString == "https://bgm.tv/oauth/authorize")
        #expect(site.tokenURL.absoluteString == "https://bgm.tv/oauth/access_token")
    }

    @Test("parses hosts from URLs and rejects junk")
    func parse() {
        #expect(BangumiSite.parse("https://bgm.tv/")?.host == "bgm.tv")
        #expect(BangumiSite.parse("BGMTV") == nil)
        #expect(BangumiSite.parse("mirror.example.com")?.host == "mirror.example.com")
        #expect(BangumiSite.parse("https://mirror.example.com/some/path")?.host == "mirror.example.com")
        #expect(BangumiSite.parse("") == nil)
        #expect(BangumiSite.parse("not a host") == nil)
        #expect(BangumiSite.parse("bangumi.lat")?.isOfficial == false)
        #expect(BangumiSite.parse("bgm.tv")?.isOfficial == true)
    }

    @Test("defaults to official; selection persists; custom sites can be added and removed")
    func settings() {
        let defaults = makeDefaults()
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .official)
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv", "bangumi.lat"])

        BangumiSiteSettings.select(.mirrorLat, defaults: defaults)
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .mirrorLat)

        let added = BangumiSiteSettings.addCustomSite("https://mirror.example.com", defaults: defaults)
        #expect(added?.host == "mirror.example.com")
        #expect(BangumiSiteSettings.addCustomSite("mirror.example.com", defaults: defaults) == nil)
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv", "bangumi.lat", "mirror.example.com"])

        // 选中自定义站，再删除它时回到官方
        BangumiSiteSettings.select(BangumiSite(host: "mirror.example.com", name: "mirror"), defaults: defaults)
        BangumiSiteSettings.removeCustomSite(host: "mirror.example.com", defaults: defaults)
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .official)
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv", "bangumi.lat"])
    }

    @Test("oauth config derives endpoints from the site")
    func oauthConfig() {
        let official = BangumiOAuthConfig.forSite(.official)
        #expect(official.authorizeURL.absoluteString == "https://bgm.tv/oauth/authorize")
        #expect(official.tokenURL.absoluteString == "https://bgm.tv/oauth/access_token")

        let mirror = BangumiOAuthConfig.forSite(.mirrorLat)
        #expect(mirror.authorizeURL.absoluteString == "https://bgm.tv/oauth/authorize")
        #expect(mirror.tokenURL.absoluteString == "https://bgm.tv/oauth/access_token")
        // 凭证与回调地址不受站点影响
        #expect(mirror.redirectURI == official.redirectURI)
        #expect(mirror.clientID == official.clientID)
    }
}
