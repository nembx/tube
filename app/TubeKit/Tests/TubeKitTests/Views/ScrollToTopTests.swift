import CoreGraphics
import Testing
@testable import TubeKit

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

    /// 镜像 dock 圆钮时两颗要像一对：圆心离边的距离得放得下整颗按钮，
    /// 探进 dock 那一行的深度也不能把按钮整个推出屏幕外。
    @Test("dock mirror keeps the whole button on screen")
    func dockMirrorStaysOnScreen() {
        let radius = ScrollToTopLayout.buttonDiameter / 2
        #expect(ScrollToTopLayout.dockCircleCenterEdgeInset >= radius)
        #expect(ScrollToTopLayout.dockCircleCenterBelowSafeArea > 0)
        // 安全区底边以下还有 dock 那一行（home 指示条 + dock），按钮不会越过屏幕底。
        #expect(ScrollToTopLayout.dockCircleCenterBelowSafeArea + radius < 83)
    }

    @Test("threshold is overridable per page")
    func customThreshold() {
        #expect(ScrollToTopLayout.shouldShow(offset: 120, threshold: 100))
        #expect(ScrollToTopLayout.shouldShow(offset: 120, threshold: 800) == false)
    }
}

@Suite("Scroll to top 露脸时机")
struct ScrollToTopRevealTests {
    private let threshold = ScrollToTopLayout.threshold
    private let slop = ScrollToTopVisibility.directionSlop

    @Test("默认模式滚过阈值就一直挂着，往回抖一下也不收")
    func pastThresholdStaysVisible() {
        var visibility = ScrollToTopVisibility(reveal: .pastThreshold)
        visibility.update(offset: threshold + 100)
        #expect(visibility.isVisible)
        visibility.update(offset: threshold + 40)
        #expect(visibility.isVisible)
        visibility.update(offset: threshold - 1)
        #expect(visibility.isVisible == false)
    }

    @Test("主页模式：往下滚过阈值才露面")
    func revealsWhileScrollingDown() {
        var visibility = ScrollToTopVisibility(reveal: .whileScrollingDown)
        visibility.update(offset: threshold - 10)
        #expect(visibility.isVisible == false)
        visibility.update(offset: threshold + 100)
        #expect(visibility.isVisible)
    }

    @Test("主页模式：手指往回一走就收起，与 dock 展开同步")
    func hidesWhenScrollingUp() {
        var visibility = ScrollToTopVisibility(reveal: .whileScrollingDown)
        visibility.update(offset: threshold + 100)
        visibility.update(offset: threshold + 100 - slop)
        #expect(visibility.isVisible == false)

        // 再往下走够一个容差又露面。
        visibility.update(offset: threshold + 100)
        #expect(visibility.isVisible)
    }

    @Test("零碎抖动不翻方向")
    func jitterKeepsDirection() {
        var visibility = ScrollToTopVisibility(reveal: .whileScrollingDown)
        visibility.update(offset: threshold + 100)
        visibility.update(offset: threshold + 101)
        visibility.update(offset: threshold + 99)
        visibility.update(offset: threshold + 100)
        #expect(visibility.isVisible)
    }

    @Test("连续反向的小步位移攒够容差才收起")
    func smallUpwardStepsAccumulate() {
        var visibility = ScrollToTopVisibility(reveal: .whileScrollingDown)
        let start = threshold + 100
        visibility.update(offset: start)
        var offset = start
        for _ in 0..<Int(slop) - 1 {
            offset -= 1
            visibility.update(offset: offset)
            #expect(visibility.isVisible)
        }
        offset -= 1
        visibility.update(offset: offset)
        #expect(visibility.isVisible == false)
    }

    @Test("回到阈值以内一律收起，锚点跟着走")
    func withinThresholdHides() {
        var visibility = ScrollToTopVisibility(reveal: .whileScrollingDown)
        visibility.update(offset: threshold + 100)
        visibility.update(offset: 50)
        #expect(visibility.isVisible == false)
        // 从阈值内直接滚过去，不用先补掉之前的位移。
        visibility.update(offset: threshold + slop + 1)
        #expect(visibility.isVisible)
    }
}
