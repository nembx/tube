import Foundation
import Testing
@testable import CezzuKit

@Suite("PlayerOverlayVisibility")
struct PlayerOverlayVisibilityTests {

    private func visibility(
        controlsVisible: Bool = false,
        isTemporaryBoosting: Bool = false,
        isBuffering: Bool = false,
        phase: PlaybackCoordinator.Phase,
        duration: TimeInterval = 1440
    ) -> PlayerOverlayVisibility {
        PlayerOverlayVisibility(
            controlsVisible: controlsVisible,
            isTemporaryBoosting: isTemporaryBoosting,
            isBuffering: isBuffering,
            phase: phase,
            duration: duration
        )
    }

    // MARK: - 备片

    @Test("备片时控制层照摆，只是播放键灰着、进度条走跑马灯")
    func preparingKeepsChromeWithControlsDisabled() {
        for phase in [PlaybackCoordinator.Phase.idle, .extracting, .loading] {
            let v = visibility(isBuffering: true, phase: phase)

            #expect(v.isPreparing)
            #expect(v.showsControls)
            #expect(!v.playbackControlsEnabled)
            #expect(v.showsIndeterminateProgress)
            #expect(v.showsPreparingScrim)
        }
    }

    @Test("备片时播放手势失效")
    func preparingBlocksPlaybackGestures() {
        let v = visibility(controlsVisible: true, isBuffering: true, phase: .extracting)

        #expect(!v.allowsPlaybackInteraction)
    }

    @Test("备片时摆载入提示，但不算缓冲")
    func preparingShowsLoadingIndicator() {
        let v = visibility(isBuffering: true, phase: .extracting)

        #expect(!v.isRebuffering)
        #expect(v.showsLoadingIndicator)
    }

    // MARK: - 缓冲

    @Test("缓冲时进度条照常可拖，手势也不拦")
    func rebufferingKeepsPlaybackControls() {
        let v = visibility(controlsVisible: true, isBuffering: true, phase: .playing)

        #expect(!v.isPreparing)
        #expect(v.isRebuffering)
        #expect(v.showsControls)
        #expect(v.playbackControlsEnabled)
        #expect(v.allowsPlaybackInteraction)
        #expect(!v.showsIndeterminateProgress)
        #expect(!v.showsPreparingScrim)
    }

    @Test("控制层叫出来也不许把载入提示藏掉")
    func loadingIndicatorSurvivesControls() {
        let hidden = visibility(controlsVisible: false, isBuffering: true, phase: .playing)
        #expect(!hidden.showsControls)
        #expect(hidden.showsLoadingIndicator)

        let shown = visibility(controlsVisible: true, isBuffering: true, phase: .playing)
        #expect(shown.showsControls)
        #expect(shown.showsLoadingIndicator)
    }

    @Test("暂停着缓冲时提示照摆，跟控制层收没收无关")
    func rebufferingWhilePausedKeepsIndicator() {
        let v = visibility(controlsVisible: false, isBuffering: true, phase: .paused)

        #expect(v.isRebuffering)
        #expect(!v.showsControls)
        #expect(v.showsLoadingIndicator)
    }

    @Test("时长还没报上来时进度条也走跑马灯")
    func unknownDurationKeepsMarquee() {
        for duration in [0, .infinity, TimeInterval.nan] {
            let v = visibility(controlsVisible: true, isBuffering: true, phase: .playing, duration: duration)

            #expect(!v.isPreparing)
            #expect(!v.hasKnownDuration)
            #expect(v.showsIndeterminateProgress)
            // 只是画不出进度，播放键该能按还是能按。
            #expect(v.playbackControlsEnabled)
        }
    }

    @Test("时长报上来之后进度条恢复正常")
    func knownDurationDropsMarquee() {
        let v = visibility(controlsVisible: true, phase: .playing, duration: 1440)

        #expect(v.hasKnownDuration)
        #expect(!v.showsIndeterminateProgress)
    }

    @Test("不缓冲也不备片时没有载入提示")
    func idlePlaybackHasNoIndicator() {
        let v = visibility(controlsVisible: true, isBuffering: false, phase: .playing)

        #expect(!v.showsLoadingIndicator)
    }

    // MARK: - 常态

    @Test("正在播且控制层展开时，两头都在")
    func playingWithControlsShown() {
        let v = visibility(controlsVisible: true, phase: .playing)

        #expect(v.showsControls)
        #expect(!v.showsTemporaryBoostBadge)
    }

    @Test("正在播且控制层收起时，整层一起退场")
    func playingWithControlsHidden() {
        let v = visibility(controlsVisible: false, phase: .playing)

        #expect(!v.showsControls)
    }

    @Test("暂停时控制层可以收走 —— 按下暂停常常就是为了看清这一帧")
    func pausedAllowsHidingControls() {
        #expect(!visibility(controlsVisible: false, phase: .paused).showsControls)
        #expect(visibility(controlsVisible: true, phase: .paused).showsControls)
    }

    @Test("放完了控制层常驻 —— 那时候没有别的出口")
    func finishedKeepsControls() {
        let v = visibility(controlsVisible: false, phase: .finished)

        #expect(v.showsControls)
    }

    @Test("失败时控制层常驻，播放键仍可按 —— 重试要走它")
    func failedKeepsControls() {
        let v = visibility(controlsVisible: false, phase: .failed(message: "boom"))

        #expect(!v.isPreparing)
        #expect(v.showsControls)
        #expect(v.playbackControlsEnabled)
        #expect(v.allowsPlaybackInteraction)
    }

    // MARK: - 长按倍速

    @Test("长按倍速期间只留倍速角标")
    func temporaryBoostHidesEverythingElse() {
        let v = visibility(controlsVisible: true, isTemporaryBoosting: true, phase: .playing)

        #expect(!v.showsControls)
        #expect(v.showsTemporaryBoostBadge)
    }

    @Test("长按倍速盖过缓冲小条和常驻理由")
    func temporaryBoostOverridesBufferingAndPause() {
        let v = visibility(
            controlsVisible: true,
            isTemporaryBoosting: true,
            isBuffering: true,
            phase: .paused
        )

        #expect(!v.showsControls)
        #expect(!v.showsLoadingIndicator)
        #expect(v.showsTemporaryBoostBadge)
    }
}
