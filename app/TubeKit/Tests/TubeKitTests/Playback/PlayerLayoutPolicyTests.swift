import Testing

@testable import TubeKit

@Suite("PlayerLayoutPolicy")
struct PlayerLayoutPolicyTests {
    @Test("宽屏无论横竖都是播放器 + 右侧详情")
    func regularWidthAlwaysWide() {
        #expect(PlayerLayoutPolicy.mode(isCompact: false, isLandscape: true) == .wide)
        #expect(PlayerLayoutPolicy.mode(isCompact: false, isLandscape: false) == .wide)
    }

    @Test("手机竖屏是上播放器下详情")
    func compactPortraitStacks() {
        #expect(PlayerLayoutPolicy.mode(isCompact: true, isLandscape: false) == .portraitStack)
    }

    @Test("手机横屏整屏播放，详情让位")
    func compactLandscapeIsImmersive() {
        #expect(PlayerLayoutPolicy.mode(isCompact: true, isLandscape: true) == .immersive)
    }
}
