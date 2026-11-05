import Foundation
import Testing
@testable import TubeKit

@Suite("ContinueWatching layout")
struct ContinueWatchingLayoutTests {
    @Test("cover is landscape: wider than tall (高小宽大)")
    func coverIsLandscape() {
        #expect(ContinueWatchingLayout.coverAspectRatio > 1)
        #expect(ContinueWatchingLayout.cardWidth > ContinueWatchingLayout.coverHeight)
    }

    @Test("cover aspect is 16:9")
    func coverAspectIsSixteenByNine() {
        #expect(abs(ContinueWatchingLayout.coverAspectRatio - 16.0 / 9.0) < 0.0001)
    }

    /// 文字压在图上之后，卡片高度就是封面本身，不再另留标题 / 副信息两条。
    @Test("the card is just the cover")
    func cardIsJustTheCover() {
        #expect(ContinueWatchingLayout.cardHeight == ContinueWatchingLayout.coverHeight)
    }

    /// 渐变要从底沿往上铺一截把文字托住，但不能盖满整张图。
    @Test("the caption gradient covers the lower part of the cover only")
    func captionGradientCoversLowerPart() {
        #expect(ContinueWatchingLayout.overlayHeightRatio > 0.5)
        #expect(ContinueWatchingLayout.overlayHeightRatio < 1)
    }

    @Test("meta line reports the episode and the resume position")
    func metaText() {
        #expect(ContinueWatchingLayout.metaText(episodeIndex: 2, positionMs: 0) == "第 3 集")
        #expect(
            ContinueWatchingLayout.metaText(episodeIndex: 2, positionMs: 754_000)
                == "第 3 集 · 看到 12:34"
        )
    }

    @Test("positions over an hour roll over to h:mm:ss")
    func positionText() {
        #expect(ContinueWatchingLayout.positionText(ms: 0) == "0:00")
        #expect(ContinueWatchingLayout.positionText(ms: 62_000) == "1:02")
        #expect(ContinueWatchingLayout.positionText(ms: 3_762_000) == "1:02:42")
        #expect(ContinueWatchingLayout.positionText(ms: -5) == "0:00")
    }

    @Test("continue watching preview limit is 20")
    func continueWatchingLimitIs20() {
        #expect(HistoryStore.continueWatchingLimit == 20)
    }
}
