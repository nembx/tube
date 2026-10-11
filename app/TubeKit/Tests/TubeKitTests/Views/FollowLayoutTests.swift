import CoreGraphics
import Testing
@testable import TubeKit

@Suite("FollowLayout")
struct FollowLayoutTests {

    private func item(id: Int) -> BangumiItem {
        BangumiItem(
            id: id,
            name: "name-\(id)",
            nameCn: "",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: BangumiImages(large: "", common: "", medium: "", small: "", grid: ""),
            tags: [],
            ratingTotal: 0,
            eps: 0,
            platform: "",
            episodeDuration: ""
        )
    }

    @Test("the compact backdrop grows by the status bar inset so it reaches the top edge")
    func compactBackdropCoversTopInset() {
        #expect(FollowLayout.compactBackdropHeight(topInset: 59)
            == FollowLayout.compactHeaderHeight + 59)
    }

    /// 宽屏 / 无安全区时不该反过来把头图压矮。
    @Test("a zero or negative inset leaves the backdrop at its base height")
    func compactBackdropIgnoresNonPositiveInset() {
        #expect(FollowLayout.compactBackdropHeight(topInset: 0) == FollowLayout.compactHeaderHeight)
        #expect(FollowLayout.compactBackdropHeight(topInset: -20) == FollowLayout.compactHeaderHeight)
    }

    @Test("the backdrop takes no extra height while the scroll sits at rest")
    func backdropDoesNotStretchAtRest() {
        #expect(FollowLayout.compactBackdropStretch(minY: -59, topInset: 59) == 0)
        #expect(FollowLayout.compactBackdropStretch(minY: 0, topInset: 0) == 0)
    }

    /// 上滚时头图跟着走，不许反向缩。
    @Test("scrolling up never shrinks the backdrop")
    func backdropDoesNotShrinkWhenScrolledUp() {
        #expect(FollowLayout.compactBackdropStretch(minY: -300, topInset: 59) == 0)
    }

    @Test("pulling down hands the drag distance to the backdrop")
    func backdropStretchesByTheDragDistance() {
        #expect(FollowLayout.compactBackdropStretch(minY: -19, topInset: 59) == 40)
        #expect(FollowLayout.compactBackdropStretch(minY: 120, topInset: 0) == 120)
    }

    @Test("the collection stack keeps the newest few, newest first")
    func stackKeepsNewestFew() {
        let items = (1...6).map { item(id: $0) }
        let stack = FollowLayout.stackItems(items)
        #expect(stack.count == FollowLayout.stackLimit)
        #expect(stack.first?.id == 1)
    }

    @Test("an empty or short collection does not pad the stack")
    func stackHandlesShortInput() {
        #expect(FollowLayout.stackItems([]).isEmpty)
        #expect(FollowLayout.stackItems([item(id: 9)]).count == 1)
    }

    @Test("each card behind the front one shifts right, tilts more and shrinks")
    func stackFansOutMonotonically() {
        for index in 1..<FollowLayout.stackLimit {
            #expect(FollowLayout.stackOffsetX(for: index) > FollowLayout.stackOffsetX(for: index - 1))
            #expect(FollowLayout.stackRotation(for: index) > FollowLayout.stackRotation(for: index - 1))
            #expect(FollowLayout.stackScale(for: index) < FollowLayout.stackScale(for: index - 1))
        }
    }

    @Test("the front card sits unshifted, unrotated and at full size")
    func frontCardIsUntransformed() {
        #expect(FollowLayout.stackOffsetX(for: 0) == 0)
        #expect(FollowLayout.stackRotation(for: 0) == 0)
        #expect(FollowLayout.stackScale(for: 0) == 1)
    }

    /// 堆得再深也不能把封面缩没了 —— 卡片数万一涨上去，缩放要有地板。
    @Test("the shrink factor never collapses the card")
    func stackScaleHasAFloor() {
        #expect(FollowLayout.stackScale(for: 100) >= 0.5)
    }

    @Test("the stack is dropped on narrow windows so the title keeps the width")
    func stackNeedsRoom() {
        #expect(!FollowLayout.showsStack(width: 600))
        #expect(FollowLayout.showsStack(width: FollowLayout.stackMinimumWidth))
        #expect(FollowLayout.showsStack(width: 1440))
    }

    @Test("the count label reads the collection size, empty included")
    func countLabelReadsTheSize() {
        #expect(FollowLayout.countLabel(0) == "已收藏 0 部")
        #expect(FollowLayout.countLabel(12) == "已收藏 12 部")
    }

    @Test("the wide header is taller than the compact one")
    func regularHeaderIsTaller() {
        #expect(FollowLayout.regularHeaderHeight > FollowLayout.compactHeaderHeight)
    }

    /// 模糊会把边缘吸淡，底图必须超铺一圈才不会露出没铺满的边。
    @Test("the blurred backdrop overscans its frame")
    func backdropOverscans() {
        #expect(FollowLayout.backdropOverscan > 1)
    }

    @Test("the page background follows the color scheme")
    func pageBackgroundFollowsScheme() {
        #expect(FollowLayout.pageBackground(.dark) == RegularShellLayout.cinemaBackground)
        #expect(FollowLayout.pageBackground(.light) == FollowLayout.lightPageBackground)
    }

    /// 两个模式给出同一个颜色的话，切换明暗就等于没切 —— 页面又变回恒定深色了。
    @Test("the two schemes do not collapse onto one background")
    func pageBackgroundDiffersBetweenSchemes() {
        #expect(FollowLayout.pageBackground(.dark) != FollowLayout.pageBackground(.light))
    }

    /// 浅色模式要把封面提亮，蒙版得刷白；刷黑就又是一块深色顶区。
    @Test("the backdrop scrim flips with the color scheme")
    func backdropScrimFlips() {
        #expect(FollowLayout.backdropScrim(.dark) == .black)
        #expect(FollowLayout.backdropScrim(.light) == .white)
        #expect(FollowLayout.backdropScrimOpacity(.dark) == FollowLayout.backdropDim)
        #expect(FollowLayout.backdropScrimOpacity(.light) == FollowLayout.lightBackdropDim)
    }

    /// 蒙版太薄就盖不住封面本身的深浅，标题会在某些封面上糊掉。
    @Test("the light scrim covers more than the dark one")
    func lightScrimIsHeavier() {
        #expect(FollowLayout.lightBackdropDim > FollowLayout.backdropDim)
        #expect(FollowLayout.lightBackdropDim < 1)
    }

    /// 空态渐变的起点也得跟着明暗走，否则浅色模式下顶上糊一块深紫。
    @Test("the empty backdrop top follows the color scheme")
    func emptyBackdropTopFollowsScheme() {
        #expect(FollowLayout.emptyBackdropTop(.dark) != FollowLayout.emptyBackdropTop(.light))
        #expect(FollowLayout.emptyBackdropTop(.dark) == CoverColorPalette.fallback.darkened.color)
    }
}
