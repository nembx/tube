import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("DetailLayout")
struct DetailLayoutTests {

    @Test("hero takes a fixed share of the viewport and leaves content below")
    func heroHeightFollowsViewport() {
        let viewport = CGSize(width: 390, height: 844)
        let height = DetailLayout.heroHeight(viewportSize: viewport)
        #expect(abs(height - viewport.height * DetailLayout.heroHeightRatio) < 0.001)
        #expect(height < viewport.height)
    }

    @Test("wide windows give the hero less of the viewport")
    func wideHeroIsShorter() {
        let height: CGFloat = 1000
        let narrow = DetailLayout.heroHeight(viewportSize: CGSize(width: 390, height: height))
        let wide = DetailLayout.heroHeight(viewportSize: CGSize(width: 900, height: height))
        #expect(wide < narrow)
    }

    @Test("a tiny viewport still gets a usable hero")
    func heroHeightClampsOnTinyViewport() {
        let height = DetailLayout.heroHeight(viewportSize: CGSize(width: 320, height: 200))
        #expect(height == DetailLayout.heroMinHeight)
    }

    @Test("horizontal padding widens with the window")
    func horizontalPaddingSteps() {
        #expect(DetailLayout.horizontalPadding(width: 390) == 24)
        #expect(DetailLayout.horizontalPadding(width: DetailLayout.wideThreshold) == 44)
        #expect(DetailLayout.horizontalPadding(width: 1200) == 64)
    }

    @Test("content width is the padded viewport, capped for readability")
    func contentWidthIsPaddedAndCapped() {
        let narrow = DetailLayout.contentWidth(viewportWidth: 390)
        #expect(abs(narrow - (390 - 24 * 2)) < 0.001)

        // 超宽窗口下夹到可读上限，而不是一路铺开
        let wide = DetailLayout.contentWidth(viewportWidth: 2000)
        #expect(abs(wide - (DetailLayout.contentMaxWidth - 64 * 2)) < 0.001)
    }

    @Test("content width never goes negative on an absurdly narrow viewport")
    func contentWidthNeverNegative() {
        #expect(DetailLayout.contentWidth(viewportWidth: 0) == 0)
        #expect(DetailLayout.contentWidth(viewportWidth: 30) == 0)
    }

    @Test("bottom inset always clears the floating dock")
    func bottomInsetClearsDock() {
        #expect(DetailLayout.bottomInset(safeAreaBottom: 0) == DetailLayout.minBottomInset)
        let tall = DetailLayout.bottomInset(safeAreaBottom: 120)
        #expect(tall == 120 + DetailLayout.dockClearance)
        #expect(tall > DetailLayout.minBottomInset)
    }
}
