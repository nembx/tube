import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("Scroll to top")
struct ScrollToTopTests {
    @Test("button stays hidden until the content top is far enough away")
    func hiddenWithinThreshold() {
        #expect(ScrollToTopLayout.shouldShow(offset: 0) == false)
        #expect(ScrollToTopLayout.shouldShow(offset: ScrollToTopLayout.threshold) == false)
        #expect(ScrollToTopLayout.shouldShow(offset: ScrollToTopLayout.threshold + 1))
    }

    @Test("rubber banding above the top keeps the button hidden")
    func negativeOffsetStaysHidden() {
        #expect(ScrollToTopLayout.shouldShow(offset: -200) == false)
    }

    @Test("anchor recycled off screen still counts as scrolled")
    func recycledAnchorShowsButton() {
        // 锚点行被卸载时偏移量退回默认值，语义是「顶端早看不见了」。
        #expect(ScrollToTopLayout.shouldShow(offset: ScrollToTopOffsetKey.defaultValue))
    }

    @Test("圆钮整个都是命中区，不小于系统最小触控目标")
    func buttonMeetsMinimumHitTarget() {
        #expect(ScrollToTopLayout.buttonDiameter >= 44)
    }

    @Test("threshold is overridable per page")
    func customThreshold() {
        #expect(ScrollToTopLayout.shouldShow(offset: 120, threshold: 100))
        #expect(ScrollToTopLayout.shouldShow(offset: 120, threshold: 800) == false)
    }
}
