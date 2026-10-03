import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("PlayerDetailScrollChrome")
struct PlayerDetailScrollChromeTests {

    @Test("顶部附近不露回顶按钮")
    func hiddenNearTop() {
        #expect(!PlayerDetailScrollChrome.showsBackToTop(scrollOffset: 0))
        #expect(!PlayerDetailScrollChrome.showsBackToTop(scrollOffset: 120))
    }

    @Test("滚过阈值才露面")
    func shownPastThreshold() {
        #expect(
            PlayerDetailScrollChrome.showsBackToTop(
                scrollOffset: PlayerDetailScrollChrome.backToTopThreshold + 1
            )
        )
        #expect(PlayerDetailScrollChrome.showsBackToTop(scrollOffset: 2000))
    }

    @Test("正好卡在阈值上不算滚过")
    func atThresholdStaysHidden() {
        #expect(
            !PlayerDetailScrollChrome.showsBackToTop(
                scrollOffset: PlayerDetailScrollChrome.backToTopThreshold
            )
        )
    }

    @Test("橡皮筋回弹的负位移不会让按钮冒出来")
    func rubberBandOffsetStaysHidden() {
        #expect(!PlayerDetailScrollChrome.showsBackToTop(scrollOffset: -300))
    }
}
