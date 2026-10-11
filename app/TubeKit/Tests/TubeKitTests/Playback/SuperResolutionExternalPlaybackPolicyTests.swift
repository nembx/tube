import Foundation
import Testing

@testable import TubeKit

@Suite("投屏时的超分降级")
struct SuperResolutionExternalPlaybackPolicyTests {

    @Test("不投屏时用户选什么就是什么")
    func keepsPreferenceWhenLocal() {
        #expect(
            SuperResolutionExternalPlaybackPolicy.effectiveMode(
                preferred: .anime4KFast,
                isExternalPlaybackActive: false
            ) == .anime4KFast
        )
    }

    @Test("投屏中一律降回 off")
    func forcesOffWhileCasting() {
        #expect(
            SuperResolutionExternalPlaybackPolicy.effectiveMode(
                preferred: .anime4KFast,
                isExternalPlaybackActive: true
            ) == .off
        )
    }

    @Test("本来就是 off 的不受影响")
    func offStaysOff() {
        #expect(
            SuperResolutionExternalPlaybackPolicy.effectiveMode(
                preferred: .off,
                isExternalPlaybackActive: true
            ) == .off
        )
    }
}
