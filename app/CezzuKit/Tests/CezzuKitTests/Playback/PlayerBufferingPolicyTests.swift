import Testing
@testable import CezzuKit

@Suite("PlayerBufferingPolicy")
struct PlayerBufferingPolicyTests {

    @Test("startup buffers less than steady state hands back to the system")
    func startupIsCheaperThanSteady() {
        let policy = PlayerBufferingPolicy.default

        #expect(policy.forwardBufferSeconds(at: .startup) > 0)
        // 稳态用 0 表示「交回 AVPlayer 自适应」，不是「不缓冲」。
        #expect(policy.forwardBufferSeconds(at: .steady) == 0)
        #expect(policy.peakBitRate(at: .startup) > 0)
        #expect(policy.peakBitRate(at: .steady) == 0)
    }

    @Test("a custom policy is honoured at both stages")
    func customPolicy() {
        let policy = PlayerBufferingPolicy(
            startupForwardBufferSeconds: 2,
            steadyForwardBufferSeconds: 30,
            startupPeakBitRate: 800_000,
            steadyPeakBitRate: 9_000_000
        )

        #expect(policy.forwardBufferSeconds(at: .startup) == 2)
        #expect(policy.forwardBufferSeconds(at: .steady) == 30)
        #expect(policy.peakBitRate(at: .startup) == 800_000)
        #expect(policy.peakBitRate(at: .steady) == 9_000_000)
    }
}

@Suite("PlayerBufferingStageMachine")
struct PlayerBufferingStageMachineTests {

    @Test("starts in startup and settles once playback actually keeps up")
    func settlesWhenPlaying() {
        var machine = PlayerBufferingStageMachine()
        #expect(machine.stage == .startup)

        #expect(machine.update(isPlaying: false, isLikelyToKeepUp: true) == false)
        #expect(machine.stage == .startup)

        #expect(machine.update(isPlaying: true, isLikelyToKeepUp: false) == false)
        #expect(machine.stage == .startup)

        #expect(machine.update(isPlaying: true, isLikelyToKeepUp: true) == true)
        #expect(machine.stage == .steady)
    }

    @Test("a mid-playback stall does not drag the policy back to startup")
    func stallKeepsSteady() {
        var machine = PlayerBufferingStageMachine()
        machine.update(isPlaying: true, isLikelyToKeepUp: true)

        // 中段缓冲是自适应算法的事，重新收紧参数只会让它更难恢复。
        #expect(machine.update(isPlaying: false, isLikelyToKeepUp: false) == false)
        #expect(machine.stage == .steady)
    }

    @Test("restart reports a change only when leaving steady state")
    func restartIsIdempotent() {
        var machine = PlayerBufferingStageMachine()
        #expect(machine.restart() == false)

        machine.update(isPlaying: true, isLikelyToKeepUp: true)
        #expect(machine.restart() == true)
        #expect(machine.stage == .startup)
        #expect(machine.restart() == false)
    }
}
