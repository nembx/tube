import Testing
@testable import CezzuKit

@Suite("PlayerOrientationPolicy")
struct PlayerOrientationPolicyTests {

    @Test("a phone stays portrait until the viewer asks for landscape")
    func phoneStaysPortraitUntilAsked() {
        #expect(
            PlayerOrientationPolicy.allowed(isPhone: true, isPlaybackPresented: false)
                == .portraitOnly
        )
        // 进播放页本身不再翻屏 —— 竖屏是播放页的默认姿势。
        #expect(
            PlayerOrientationPolicy.allowed(isPhone: true, isPlaybackPresented: true)
                == .portraitOnly
        )
        #expect(
            PlayerOrientationPolicy.allowed(
                isPhone: true, isPlaybackPresented: true, prefersLandscape: true
            ) == .landscapeOnly
        )
    }

    @Test("按过旋转键也只在播放页内有效，退出播放页一律回竖屏")
    func landscapePreferenceDoesNotOutlivePlayback() {
        #expect(
            PlayerOrientationPolicy.allowed(
                isPhone: true, isPlaybackPresented: false, prefersLandscape: true
            ) == .portraitOnly
        )
    }

    @Test("leaving the player forbids landscape rather than merely asking for portrait")
    func leavingPlaybackForbidsLandscape() {
        // 这是「详情页残留横屏」的回归护栏：光请求转回竖屏不够，必须让横屏变成
        // 不被允许的朝向，系统才不会在用户动一下手机时把界面转回去。
        let afterLeaving = PlayerOrientationPolicy.allowed(isPhone: true, isPlaybackPresented: false)

        #expect(afterLeaving != .any)
        #expect(afterLeaving != .landscapeOnly)
    }

    @Test("picture in picture counts as having left the player")
    func pictureInPictureRestoresPortrait() {
        // 画中画期间播放页已经退场，界面该跟着回竖屏，否则 App 卡在横屏。
        #expect(
            PlayerOrientationPolicy.allowed(isPhone: true, isPlaybackPresented: false)
                == .portraitOnly
        )
    }

    @Test("anything that is not a phone is left unconstrained")
    func nonPhoneIsUnconstrained() {
        #expect(PlayerOrientationPolicy.allowed(isPhone: false, isPlaybackPresented: false) == .any)
        #expect(PlayerOrientationPolicy.allowed(isPhone: false, isPlaybackPresented: true) == .any)
    }
}
