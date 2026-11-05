import CoreGraphics
import Testing
@testable import TubeKit

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

    @Test("compact grid is a fixed 3-column layout sized close to the home row cards")
    func compactColumns() {
        #expect(BangumiGridLayout.compactColumns.count == 3)
        #expect(BangumiGridLayout.compactHorizontalSpacing == BangumiSectionLayout.cardSpacing)
        // iPhone 15/16（393pt）减去两侧 20pt 边距
        let width393 = BangumiGridLayout.compactItemWidth(forWidth: 393 - 40)
        #expect(width393 > 100 && width393 < 130)
        // iPhone Plus / Max（430pt）
        let width430 = BangumiGridLayout.compactItemWidth(forWidth: 430 - 40)
        #expect(abs(width430 - BangumiSectionLayout.cardWidth) < 12)
    }

    @Test("compact columns follow the requested count and clamp to at least one")
    func compactColumnCountOverride() {
        #expect(BangumiGridLayout.compactColumns(count: 3).count == 3)
        #expect(BangumiGridLayout.compactColumns(count: 2).count == 2)
        #expect(BangumiGridLayout.compactColumns(count: 0).count == 1)
        // 默认仍是 3 列，追番页之外的调用方不受影响
        #expect(BangumiGridLayout.compactColumns.count == BangumiGridLayout.compactColumnCount)
        for item in BangumiGridLayout.compactColumns(count: 2) {
            guard case let .flexible(minimum: _, maximum: maximum) = item.size else {
                Issue.record("expected flexible GridItems")
                return
            }
            #expect(maximum == .infinity)
        }
    }

    @Test("two-column compact cards split the width minus the gutter in half")
    func compactTwoColumnItemWidth() {
        let width: CGFloat = 393 - 40
        let three = BangumiGridLayout.compactItemWidth(forWidth: width)
        let two = BangumiGridLayout.compactItemWidth(forWidth: width, count: 2)
        #expect(two > three)
        #expect(two > 160 && two < 180)
        let expected = (width - BangumiGridLayout.compactHorizontalSpacing) / 2
        #expect(abs(two - expected) < 0.001)
        // 列数非法时退化成 1 列，而不是除出负数 / 崩溃
        #expect(BangumiGridLayout.compactItemWidth(forWidth: width, count: 0) == width)
    }
}
