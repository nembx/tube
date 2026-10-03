import Testing

@testable import CezzuKit

@Suite("PlayerCloseButtonPolicy")
struct PlayerCloseButtonPolicyTests {

    @Test("手机竖屏摆返回箭头 —— 关掉播放页就是回到详情页")
    func phonePortraitShowsBack() {
        #expect(PlayerCloseButtonPolicy.style(mode: .portraitStack, isPhone: true) == .back)
    }

    @Test("手机横屏不摆左上角的键")
    func phoneLandscapeHidesButton() {
        #expect(PlayerCloseButtonPolicy.style(mode: .immersive, isPhone: true) == .hidden)
    }

    @Test("iPad / Mac 任何摆法都是关闭键")
    func nonPhoneAlwaysCloses() {
        for mode in [PlayerLayoutMode.wide, .portraitStack, .immersive] {
            #expect(PlayerCloseButtonPolicy.style(mode: mode, isPhone: false) == .close)
        }
    }
}
