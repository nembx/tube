import Foundation
import Testing
@testable import TubeKit

@Suite("PlaybackProxySettings")
struct PlaybackProxySettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "PlaybackProxySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("parses http, https and bare host:port like Kazumi's ProxyUtils")
    func parse() {
        #expect(PlaybackProxySettings.parse("http://127.0.0.1:7890")?.host == "127.0.0.1")
        #expect(PlaybackProxySettings.parse("http://127.0.0.1:7890")?.port == 7890)
        #expect(PlaybackProxySettings.parse("127.0.0.1:7890")?.port == 7890)
        #expect(PlaybackProxySettings.parse("https://proxy.lan:1080/")?.host == "proxy.lan")
        #expect(PlaybackProxySettings.parse("proxy.lan:1080")?.port == 1080)
    }

    @Test("rejects invalid proxies")
    func rejectsInvalid() {
        #expect(PlaybackProxySettings.parse("") == nil)
        #expect(PlaybackProxySettings.parse("127.0.0.1") == nil)
        #expect(PlaybackProxySettings.parse("127.0.0.1:") == nil)
        #expect(PlaybackProxySettings.parse(":7890") == nil)
        #expect(PlaybackProxySettings.parse("127.0.0.1:70000") == nil)
        #expect(!PlaybackProxySettings.isValid("socks5://127.0.0.1:7890"))
    }

    @Test("disabled by default; enabled returns a normalized http URL")
    func defaults() {
        let defaults = makeDefaults()
        #expect(PlaybackProxySettings.proxyURL(from: defaults) == nil)

        defaults.set(true, forKey: PlaybackProxySettings.enabledKey)
        // 未填写时用默认本地 Clash 端口
        #expect(PlaybackProxySettings.proxyURL(from: defaults)?.absoluteString == "http://127.0.0.1:7890")

        defaults.set("10.0.0.2:8080", forKey: PlaybackProxySettings.urlKey)
        #expect(PlaybackProxySettings.proxyURL(from: defaults)?.absoluteString == "http://10.0.0.2:8080")
    }

    @Test("enabled with an invalid address falls back to no proxy")
    func invalidWhenEnabled() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: PlaybackProxySettings.enabledKey)
        defaults.set("not-a-proxy", forKey: PlaybackProxySettings.urlKey)
        #expect(PlaybackProxySettings.proxyURL(from: defaults) == nil)
    }

    @Test("apply writes the connection proxy dictionary only when enabled")
    func applyToSession() {
        let defaults = makeDefaults()
        let config = URLSessionConfiguration.ephemeral
        PlaybackProxySettings.apply(to: config, defaults: defaults)
        #expect(config.connectionProxyDictionary == nil)

        defaults.set(true, forKey: PlaybackProxySettings.enabledKey)
        defaults.set("127.0.0.1:7890", forKey: PlaybackProxySettings.urlKey)
        PlaybackProxySettings.apply(to: config, defaults: defaults)
        let dict = config.connectionProxyDictionary
        #expect(dict?["HTTPProxy"] as? String == "127.0.0.1")
        #expect(dict?["HTTPPort"] as? Int == 7890)
        #expect(dict?["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(dict?["HTTPSPort"] as? Int == 7890)
        #expect(dict?["HTTPEnable"] as? Int == 1)
    }
}
