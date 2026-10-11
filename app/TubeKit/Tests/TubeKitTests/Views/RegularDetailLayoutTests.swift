import CoreGraphics
import Testing
@testable import TubeKit

@Suite("RegularDetailLayout")
struct RegularDetailLayoutTests {

    @Test("the hero fills the viewport minus the peek that hints at content below")
    func heroHeightIsFullBleed() {
        let viewport: CGFloat = 900
        let height = RegularDetailLayout.heroHeight(viewportHeight: viewport)
        #expect(abs(height - (viewport - RegularDetailLayout.heroBottomPeek)) < 0.001)
        // 下面必须露出来一点，否则看不出还能往下滚。
        #expect(height < viewport)
    }

    @Test("hero height clamps on tiny and huge windows")
    func heroHeightClamped() {
        #expect(RegularDetailLayout.heroHeight(viewportHeight: 0)
            == RegularDetailLayout.heroMinHeight)
        #expect(RegularDetailLayout.heroHeight(viewportHeight: 400)
            == RegularDetailLayout.heroMinHeight)
        #expect(RegularDetailLayout.heroHeight(viewportHeight: 4000)
            == RegularDetailLayout.heroMaxHeight)
    }

    @Test("the poster keeps the cover's own 3:4 ratio and never outgrows the source pixels")
    func posterKeepsCoverRatio() {
        // 源图短边约 1000px；@2x 下 440pt 高 = 880px，还在原图以内。
        #expect(RegularDetailLayout.posterMaxHeight * 2 <= 1000)
        for hero in [CGFloat(0), 420, 700, 4000] {
            let height = RegularDetailLayout.posterHeight(heroHeight: hero)
            let width = RegularDetailLayout.posterWidth(heroHeight: hero)
            #expect(height >= RegularDetailLayout.posterMinHeight)
            #expect(height <= RegularDetailLayout.posterMaxHeight)
            #expect(abs(width / height - 3.0 / 4.0) < 0.0001)
        }
    }

    @Test("text and poster never overlap on a wide window")
    func textLeavesRoomForThePoster() {
        let width: CGFloat = 1440
        let hero = RegularDetailLayout.heroHeight(viewportHeight: 900)
        #expect(RegularDetailLayout.showsPoster(width: width))
        let used = RegularDetailLayout.horizontalPadding * 2
            + RegularDetailLayout.posterWidth(heroHeight: hero)
            + RegularDetailLayout.posterFrameInset * 2
            + RegularDetailLayout.posterGap
            + RegularDetailLayout.heroTextWidth(width: width, heroHeight: hero)
        #expect(used <= width)
    }

    @Test("a narrow window drops the poster and hands the width to the copy")
    func narrowWindowDropsPoster() {
        let width = RegularDetailLayout.posterMinimumWindowWidth - 1
        let hero = RegularDetailLayout.heroHeight(viewportHeight: 800)
        #expect(!RegularDetailLayout.showsPoster(width: width))
        let text = RegularDetailLayout.heroTextWidth(width: width, heroHeight: hero)
        #expect(text == RegularDetailLayout.heroTextMaxWidth)
        #expect(text <= width - RegularDetailLayout.horizontalPadding * 2)
    }

    @Test("content stops widening past the readable cap")
    func contentWidthCapped() {
        let wide = RegularDetailLayout.contentWidth(viewportWidth: 3000)
        #expect(wide == RegularDetailLayout.contentMaxWidth - RegularDetailLayout.horizontalPadding * 2)
        // 窗口窄到内边距吃光宽度时也不能塌成 0 / 负数。
        #expect(RegularDetailLayout.contentWidth(viewportWidth: 100) >= 280)
    }

    @Test("the overview splits into two columns only when the main column stays usable")
    func twoColumnNeedsAUsableMainColumn() {
        let wide = RegularDetailLayout.contentWidth(viewportWidth: 1600)
        #expect(RegularDetailLayout.isTwoColumn(contentWidth: wide))
        #expect(
            RegularDetailLayout.mainColumnWidth(contentWidth: wide)
                >= RegularDetailLayout.mainColumnMinimumWidth
        )
        #expect(
            RegularDetailLayout.mainColumnWidth(contentWidth: wide)
                + RegularDetailLayout.sideColumnWidth
                + RegularDetailLayout.columnGap == wide
        )

        // 主栏挤不到门槛就退回单栏，整宽都归主栏。
        let narrow = RegularDetailLayout.contentWidth(viewportWidth: 820)
        #expect(!RegularDetailLayout.isTwoColumn(contentWidth: narrow))
        #expect(RegularDetailLayout.mainColumnWidth(contentWidth: narrow) == narrow)
    }

    @Test("a short window folds the hero copy into its compact form")
    func shortWindowUsesCompactHero() {
        #expect(RegularDetailLayout.isCompactHero(
            heroHeight: RegularDetailLayout.heroMinHeight
        ))
        #expect(!RegularDetailLayout.isCompactHero(
            heroHeight: RegularDetailLayout.heroMaxHeight
        ))
    }
}
