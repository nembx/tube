import Foundation
import Testing
@testable import TubeKit

@Suite("片头片尾与连续播放")
struct EpisodePlaybackAutomationTests {
    private let settings = EpisodePlaybackSettings(openingSeconds: 90, endingSeconds: 90, autoPlayNext: true)

    @Test("片头只跳一次，手动拖回不会再跳")
    func skipsOpeningOnce() {
        var automation = EpisodePlaybackAutomation()
        #expect(tick(&automation, time: 1) == .seek(90))
        #expect(tick(&automation, time: 2) == nil)
    }

    @Test("从片头之后续播不回退")
    func preservesResume() {
        var automation = EpisodePlaybackAutomation()
        #expect(tick(&automation, time: 300) == nil)
        #expect(tick(&automation, time: 1) == nil)
    }

    @Test("片尾倒计时五秒后只切换一次")
    func advancesOnce() {
        var automation = EpisodePlaybackAutomation()
        #expect(tick(&automation, time: 1310) == nil)
        #expect(automation.countdown == 5)
        for remaining in stride(from: 4, through: 1, by: -1) {
            #expect(tick(&automation, time: 1310) == nil)
            #expect(automation.countdown == remaining)
        }
        #expect(tick(&automation, time: 1310) == .nextEpisode)
        #expect(tick(&automation, time: 1310) == nil)
    }

    @Test("取消后本集不再自动切换或跳过片尾")
    func cancelsForEpisode() {
        var automation = EpisodePlaybackAutomation()
        _ = tick(&automation, time: 1310)
        automation.cancel()
        #expect(automation.countdown == nil)
        for _ in 0..<8 { #expect(tick(&automation, time: 1399) == nil) }
    }

    @Test("暂停和缓冲时倒计时不前进")
    func pausesCountdown() {
        var automation = EpisodePlaybackAutomation()
        _ = tick(&automation, time: 1310)
        #expect(automation.tick(time: 1310, duration: 1400, isPlaying: false, isBuffering: false,
                                didEnd: false, hasNext: true, settings: settings) == nil)
        #expect(automation.tick(time: 1310, duration: 1400, isPlaying: true, isBuffering: true,
                                didEnd: false, hasNext: true, settings: settings) == nil)
        #expect(automation.countdown == 5)
    }

    @Test("最后一集或关闭连续播放只跳过片尾")
    func stopsAtLastEpisode() {
        var automation = EpisodePlaybackAutomation()
        #expect(tick(&automation, time: 1310, hasNext: false) == .seek(1400))
        #expect(automation.countdown == nil)
        var disabled = EpisodePlaybackAutomation()
        var preferences = settings
        preferences.autoPlayNext = false
        #expect(disabled.tick(time: 1310, duration: 1400, isPlaying: true, isBuffering: false,
                              didEnd: false, hasNext: true, settings: preferences) == .seek(1400))
    }

    @Test("未设置片尾时自然结束仍能连播，结束后的缓冲标记不阻止倒计时")
    func advancesAfterNaturalEnd() {
        var automation = EpisodePlaybackAutomation()
        let preferences = EpisodePlaybackSettings(autoPlayNext: true)
        for _ in 0..<5 {
            #expect(automation.tick(time: 1400, duration: 1400, isPlaying: false, isBuffering: true,
                                    didEnd: true, hasNext: true, settings: preferences) == nil)
        }
        #expect(automation.tick(time: 1400, duration: 1400, isPlaying: false, isBuffering: true,
                                didEnd: true, hasNext: true, settings: preferences) == .nextEpisode)
    }

    @Test("时长未知或片头片尾超过视频长度时不跳过")
    func rejectsInvalidDuration() {
        var automation = EpisodePlaybackAutomation()
        #expect(automation.tick(time: 1, duration: .nan, isPlaying: true, isBuffering: false,
                                didEnd: false, hasNext: true, settings: settings) == nil)
        #expect(automation.tick(time: 1, duration: 100, isPlaying: true, isBuffering: false,
                                didEnd: false, hasNext: true, settings: settings) == nil)
    }

    @Test("拖出片尾区间后清除倒计时")
    func clearsCountdownOnSeekBack() {
        var automation = EpisodePlaybackAutomation()
        _ = tick(&automation, time: 1310)
        #expect(tick(&automation, time: 600) == nil)
        #expect(automation.countdown == nil)
    }

    @Test("按番剧隔离保存并限制异常秒数")
    func persistsSettings() throws {
        let suite = "EpisodePlaybackSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        EpisodePlaybackSettingsStore.save(settings, identity: "番剧 A", defaults: defaults)
        #expect(EpisodePlaybackSettingsStore.load(identity: "番剧 A", defaults: defaults) == settings)
        #expect(EpisodePlaybackSettingsStore.load(identity: "番剧 B", defaults: defaults) == EpisodePlaybackSettings())
        let invalid = EpisodePlaybackSettings(openingSeconds: -10, endingSeconds: 999)
        EpisodePlaybackSettingsStore.save(invalid, identity: "番剧 B", defaults: defaults)
        #expect(EpisodePlaybackSettingsStore.load(identity: "番剧 B", defaults: defaults).openingSeconds == 0)
        #expect(EpisodePlaybackSettingsStore.load(identity: "番剧 B", defaults: defaults).endingSeconds == 600)
    }

    private func tick(_ automation: inout EpisodePlaybackAutomation, time: Double, hasNext: Bool = true) -> EpisodePlaybackAutomation.Action? {
        automation.tick(time: time, duration: 1400, isPlaying: true, isBuffering: false,
                        didEnd: false, hasNext: hasNext, settings: settings)
    }
}
