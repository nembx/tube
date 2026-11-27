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
        #expect(site.nextDomain.absoluteString == "https://next.bgm.tv")
        #expect(site.authorizeURL.absoluteString == "https://bgm.tv/oauth/authorize")
        #expect(site.tokenURL.absoluteString == "https://bgm.tv/oauth/access_token")
    }

    @Test("mirror site derives api/lain/next subdomains")
    func mirrorDomains() {
        let site = BangumiSite.mirrorLat
        #expect(site.apiDomain.absoluteString == "https://api.bangumi.lat")
        #expect(site.webDomain.absoluteString == "https://bangumi.lat")
        #expect(site.imageDomain.absoluteString == "https://lain.bangumi.lat")
        // 镜像也代理 /p1：短评 / 长评 / 单集吐槽 / 热门不再只有官方可用。
        #expect(site.nextDomain.absoluteString == "https://next.bangumi.lat")
        // 授权页与换 token 固定官方：镜像的 token 端点没有代理，网页层在 Anubis 之后。
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
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv"])

        defaults.set("bangumi.lat", forKey: BangumiSiteSettings.selectedHostKey)
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .mirrorLat)
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv", "bangumi.lat"])

        let added = BangumiSiteSettings.addCustomSite("https://mirror.example.com", defaults: defaults)
        #expect(added?.host == "mirror.example.com")
        #expect(BangumiSiteSettings.addCustomSite("mirror.example.com", defaults: defaults) == nil)
        #expect(BangumiSiteSettings.allSites(from: defaults).contains { $0.host == "mirror.example.com" })

        // 选中自定义站，再删除它时回到官方
        BangumiSiteSettings.select(BangumiSite(host: "mirror.example.com", name: "mirror"), defaults: defaults)
        BangumiSiteSettings.removeCustomSite(host: "mirror.example.com", defaults: defaults)
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .official)
        #expect(BangumiSiteSettings.allSites(from: defaults).map(\.host) == ["bgm.tv"])
    }

    @Test("directory uses advertised hosts and skips frontend-only sites")
    func directory() throws {
        let json = """
            {"mirrors":[
              {"name":"bgm.lat","url":"https://www.bgm.lat","base":"bgm.lat","services":[
                {"id":"main","hosts":["bgm.lat","www.bgm.lat"]},
                {"id":"next","hosts":["next.bgm.lat"]},
                {"id":"api","hosts":["bad/host","api.bgm.lat"]},
                {"id":"lain","hosts":["images.bgm.lat"]}
              ]},
              {"name":"fxbgm.tv","url":"https://fxbgm.tv","base":"fxbgm.tv","services":[
                {"id":"main","hosts":["fxbgm.tv"]}
              ]}
            ]}
            """
        let sites = try BangumiMirrorDirectory.sites(from: Data(json.utf8))
        #expect(sites.map(\.host) == ["bgm.lat"])
        let site = try #require(sites.first)
        #expect(site.apiDomain.host == "api.bgm.lat")
        #expect(site.nextDomain.host == "next.bgm.lat")
        #expect(site.imageDomain.host == "images.bgm.lat")
        #expect(site.webDomain.host == "www.bgm.lat")

        let defaults = makeDefaults()
        try BangumiSiteSettings.storeMirrorSites(sites, defaults: defaults)
        #expect(BangumiSiteSettings.allSites(from: defaults) == [.official, site])
        BangumiSiteSettings.select(site, defaults: defaults)
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == site)
        #expect(BangumiSiteSettings.addCustomSite("bgm.lat", defaults: defaults) == nil)
    }

    @Test("refreshing the directory preserves existing custom mirrors")
    func customMirrorSurvivesRefresh() throws {
        let defaults = makeDefaults()
        let custom = try #require(BangumiSiteSettings.addCustomSite("mirror.example.com", defaults: defaults))
        let mirror = BangumiSite(host: custom.host, name: "目录镜像")
        BangumiSiteSettings.select(custom, defaults: defaults)
        try BangumiSiteSettings.storeMirrorSites([mirror], defaults: defaults)
        #expect(BangumiSiteSettings.allSites(from: defaults) == [.official, custom])
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == custom)

        BangumiSiteSettings.removeCustomSite(host: custom.host, defaults: defaults)
        #expect(BangumiSiteSettings.allSites(from: defaults) == [.official, mirror])
        #expect(BangumiSiteSettings.selectedSite(from: defaults) == .official)
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
