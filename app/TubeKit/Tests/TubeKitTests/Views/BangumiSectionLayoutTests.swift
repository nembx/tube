import CoreGraphics
import Testing
@testable import TubeKit

@Suite("BangumiSectionLayout")
struct BangumiSectionLayoutTests {

    @Test("cardHeight is cover (3:4) plus the title block")
    func cardHeightComposition() {
        let width: CGFloat = 130
        let expected = width / BangumiCardLayout.coverAspectRatio
            + BangumiCardLayout.spacing
            + BangumiCardLayout.titleHeight
        #expect(BangumiSectionLayout.cardHeight(cardWidth: width) == expected)
    }

    @Test("the default cardHeight matches the compact card width")
    func defaultMatchesCompactWidth() {
        #expect(
            BangumiSectionLayout.cardHeight
                == BangumiSectionLayout.cardHeight(cardWidth: BangumiSectionLayout.cardWidth)
        )
    }

    @Test("the wide-screen card is taller than the compact one")
    func regularCardIsLarger() {
        #expect(BangumiSectionLayout.regularCardWidth > BangumiSectionLayout.cardWidth)
        #expect(
            BangumiSectionLayout.cardHeight(cardWidth: BangumiSectionLayout.regularCardWidth)
                > BangumiSectionLayout.cardHeight
        )
    }

    @Test("a zero width degenerates to the title block only")
    func zeroWidth() {
        #expect(
            BangumiSectionLayout.cardHeight(cardWidth: 0)
                == BangumiCardLayout.spacing + BangumiCardLayout.titleHeight
        )
    }
}
