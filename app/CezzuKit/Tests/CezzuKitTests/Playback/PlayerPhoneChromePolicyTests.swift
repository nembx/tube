import Testing

@testable import CezzuKit

@Suite("PlayerPhoneChromePolicy")
struct PlayerPhoneChromePolicyTests {

    @Test("手机竖屏走手机那套摆件")
    func phonePortrait() {
        #expect(PlayerPhoneChromePolicy.usesPhonePortraitChrome(mode: .portraitStack, isPhone: true))
        #expect(!PlayerPhoneChromePolicy.usesPhoneLandscapeChrome(mode: .portraitStack, isPhone: true))
    }

    @Test("手机横屏走横屏那套摆件")
    func phoneLandscape() {
        #expect(PlayerPhoneChromePolicy.usesPhoneLandscapeChrome(mode: .immersive, isPhone: true))
        #expect(!PlayerPhoneChromePolicy.usesPhonePortraitChrome(mode: .immersive, isPhone: true))
    }

    @Test("iPad 窄分屏落进 portraitStack 也不跟着改摆法")
    func padCompactKeepsRegularChrome() {
        #expect(!PlayerPhoneChromePolicy.usesPhonePortraitChrome(mode: .portraitStack, isPhone: false))
        #expect(!PlayerPhoneChromePolicy.usesPhoneLandscapeChrome(mode: .immersive, isPhone: false))
    }

    @Test("宽屏摆法两套都不走")
    func wideUsesNeither() {
        #expect(!PlayerPhoneChromePolicy.usesPhonePortraitChrome(mode: .wide, isPhone: true))
        #expect(!PlayerPhoneChromePolicy.usesPhoneLandscapeChrome(mode: .wide, isPhone: true))
    }
}
