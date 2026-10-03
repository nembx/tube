import Foundation
import Testing
@testable import CezzuKit

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

    @Test("card height includes title and meta bands")
    func cardHeightIncludesTextBands() {
        let expected =
            ContinueWatchingLayout.coverHeight
            + ContinueWatchingLayout.spacing
            + ContinueWatchingLayout.titleHeight
            + 2
            + ContinueWatchingLayout.metaHeight
        #expect(ContinueWatchingLayout.cardHeight == expected)
    }

    @Test("continue watching preview limit is 20")
    func continueWatchingLimitIs20() {
        #expect(HistoryStore.continueWatchingLimit == 20)
    }
}
