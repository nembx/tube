import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("BangumiGrid layout")
struct BangumiGridLayoutTests {
    @Test("falls back to one column when width is unknown or non-positive")
    func fallsBackForInvalidWidth() {
        #expect(BangumiGridLayout.columnCount(forWidth: 0) == 1)
        #expect(BangumiGridLayout.columnCount(forWidth: -10) == 1)
        #expect(BangumiGridLayout.columnCount(forWidth: .nan) == 1)
        #expect(BangumiGridLayout.columnCount(forWidth: .infinity) == 1)
    }

    @Test("fits a single preferred card on narrow phones")
    func singleColumnOnNarrowWidth() {
        let justOne = BangumiGridLayout.preferredItemWidth
        #expect(BangumiGridLayout.columnCount(forWidth: justOne) == 1)

        let almostTwo = 2 * BangumiGridLayout.preferredItemWidth
            + BangumiGridLayout.horizontalSpacing
            - 1
        #expect(BangumiGridLayout.columnCount(forWidth: almostTwo) == 1)
    }

    @Test("grows columns as the container gets wider")
    func growsWithWidth() {
        let spacing = BangumiGridLayout.horizontalSpacing
        let preferred = BangumiGridLayout.preferredItemWidth

        // 刚好塞下 3 列：3 * preferred + 2 * spacing
        let threeColumnWidth = 3 * preferred + 2 * spacing
        #expect(BangumiGridLayout.columnCount(forWidth: threeColumnWidth) == 3)

        // 差 1pt 不够 4 列，仍是 3
        let almostFour = 4 * preferred + 3 * spacing - 1
        #expect(BangumiGridLayout.columnCount(forWidth: almostFour) == 3)

        // 刚好 4 列
        let fourColumnWidth = 4 * preferred + 3 * spacing
        #expect(BangumiGridLayout.columnCount(forWidth: fourColumnWidth) == 4)

        // 宽屏 Mac 窗口可到 7 列
        let wide: CGFloat = 1200
        #expect(BangumiGridLayout.columnCount(forWidth: wide) == 7)
    }

    @Test("adaptive column config uses preferred min/max widths")
    func adaptiveColumnsUsePreferredBounds() {
        #expect(BangumiGridLayout.columns.count == 1)
        guard case let .adaptive(minimum: minimum, maximum: maximum) = BangumiGridLayout.columns[0].size else {
            Issue.record("expected a single adaptive GridItem")
            return
        }
        #expect(minimum == BangumiGridLayout.preferredItemWidth)
        #expect(maximum == BangumiGridLayout.maximumItemWidth)
    }

    @Test("actual cell width stays at least preferred when columns fit")
    func cellWidthAtLeastPreferredWhenFit() {
        let spacing = BangumiGridLayout.horizontalSpacing
        let preferred = BangumiGridLayout.preferredItemWidth
        let width: CGFloat = 4 * preferred + 3 * spacing + 20
        let columns = BangumiGridLayout.columnCount(forWidth: width)
        let cellWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        #expect(cellWidth + 0.001 >= preferred)
    }
}
