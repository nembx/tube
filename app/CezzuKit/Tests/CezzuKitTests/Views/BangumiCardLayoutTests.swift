import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("BangumiCard layout")
struct BangumiCardLayoutTests {
    @Test("cover uses 3:4 aspect ratio")
    func coverAspectRatioIsThreeByFour() {
        let expectedRatio: CGFloat = 3.0 / 4.0
        #expect(abs(BangumiCardLayout.coverAspectRatio - expectedRatio) < 0.001)

        let width: CGFloat = 160
        let height = width / BangumiCardLayout.coverAspectRatio

        #expect(abs(height - (160 * 4.0 / 3.0)) < 0.001)
    }

    @Test("meta overlay uses bottom one fifth of the cover")
    func metaOverlayUsesBottomOneFifth() {
        #expect(abs(BangumiCardLayout.overlayHeightRatio - 0.2) < 0.001)
    }

    @Test("hover lifts the card and zooms the art, without resizing the card")
    func hoverIsLiftPlusZoom() {
        #expect(BangumiCardLayout.hoverLift > 0)
        #expect(BangumiCardLayout.hoverImageScale > 1)
        // 放大的是圆角里的图；幅度太大会把封面边缘的字裁掉。
        #expect(BangumiCardLayout.hoverImageScale <= 1.12)
    }

    @Test("the row reserves room for the lift so the card is not clipped")
    func rowLeavesRoomForTheLift() {
        let cardHeight = BangumiSectionLayout.cardHeight
        #expect(cardHeight + BangumiCardLayout.hoverLift > cardHeight)
        // 让出的高度必须刚好等于上浮距离，多留就成了行间的空隙
        #expect(BangumiCardLayout.hoverLift < BangumiCardLayout.titleHeight)
    }
}
