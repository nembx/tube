import Testing
@testable import TubeKit

@Suite("PlayerScrubbingState")
struct PlayerScrubbingStateTests {

    @Test("sync follows playback time only when not scrubbing")
    func syncFollowsPlaybackTimeOnlyWhenInactive() {
        var state = PlayerScrubbingState()

        state.syncPlaybackTime(12)
        #expect(state.position == 12)

        state.begin(at: 12)
        state.update(position: 35)
        state.syncPlaybackTime(18)

        #expect(state.isActive == true)
        #expect(state.position == 35)
    }

    @Test("finish is idempotent and keeps the committed target")
    func finishIsIdempotent() {
        var state = PlayerScrubbingState()

        state.begin(at: 24)
        state.update(position: 57)

        let first = state.finish()
        let second = state.finish()

        #expect(first == 57)
        #expect(second == nil)
        #expect(state.isActive == false)
        #expect(state.position == 57)
    }

    @Test("finished scrub holds target position until playback catches up")
    func finishHoldsTargetUntilPlaybackCatchesUp() {
        var state = PlayerScrubbingState()

        state.begin(at: 24)
        state.update(position: 57)
        let target = state.finish()

        state.syncPlaybackTime(25)
        #expect(target == 57)
        #expect(state.position == 57)

        state.syncPlaybackTime(56.8)
        #expect(state.position == 56.8)
    }

    @Test("arrival window is wide enough for a tolerant seek to land")
    func arrivalWindowCoversSeekTolerance() {
        // 跳转允许落在 ±PlayerSeekTolerance.seconds 内，窗口窄于它就永远对不上。
        #expect(PlayerScrubbingState.arrivalWindow > PlayerSeekTolerance.seconds)

        var state = PlayerScrubbingState()
        state.begin(at: 24)
        state.update(position: 57)
        _ = state.finish()

        // 播放头落在容差边缘也要算作到位。
        state.syncPlaybackTime(57 - PlayerSeekTolerance.seconds)
        #expect(state.position == 57 - PlayerSeekTolerance.seconds)
    }

    @Test("a time far from the target is still ignored after a seek")
    func farTimesRemainIgnored() {
        var state = PlayerScrubbingState()
        state.begin(at: 24)
        state.update(position: 57)
        _ = state.finish()

        state.syncPlaybackTime(57 - PlayerScrubbingState.arrivalWindow - 0.1)
        #expect(state.position == 57)
    }
}
