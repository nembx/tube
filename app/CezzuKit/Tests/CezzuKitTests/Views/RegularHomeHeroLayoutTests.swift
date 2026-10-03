import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("RegularHomeHeroBanner")
struct RegularHomeHeroLayoutTests {

    private func item(id: Int, name: String, nameCn: String) -> BangumiItem {
        BangumiItem(
            id: id, name: name, nameCn: nameCn,
            summary: "", airDate: "", rank: 0, ratingScore: 0,
            images: .empty, tags: []
        )
    }

    @Test("the hero fills the viewport minus the peek that hints at content below")
    func contentHeightIsFullBleed() {
        let viewport: CGFloat = 900
        let expected = viewport - RegularHomeHeroLayout.bottomPeek
        #expect(expected > RegularHomeHeroLayout.minHeight)
        #expect(expected < RegularHomeHeroLayout.maxHeight)
        #expect(
            abs(RegularHomeHeroLayout.contentHeight(viewportHeight: viewport) - expected) < 0.001
        )
        // 下一行必须露出来一点，否则看不出还能往下滚。
        #expect(RegularHomeHeroLayout.contentHeight(viewportHeight: viewport) < viewport)
    }

    @Test("contentHeight clamps on tiny and huge windows")
    func contentHeightClamped() {
        #expect(RegularHomeHeroLayout.contentHeight(viewportHeight: 0)
            == RegularHomeHeroLayout.minHeight)
        #expect(RegularHomeHeroLayout.contentHeight(viewportHeight: 400)
            == RegularHomeHeroLayout.minHeight)
        #expect(RegularHomeHeroLayout.contentHeight(viewportHeight: 4000)
            == RegularHomeHeroLayout.maxHeight)
    }

    @Test("the poster never gets scaled past the source resolution")
    func posterStaysWithinSourcePixels() {
        // 源图短边约 1000px；@2x 下 480pt 高 = 960px，还在原图以内。
        #expect(RegularHomeHeroLayout.posterMaxHeight * 2 <= 1000)
        for hero in [CGFloat(420), 600, 900, 4000] {
            let height = RegularHomeHeroLayout.posterHeight(heroHeight: hero)
            #expect(height >= RegularHomeHeroLayout.posterMinHeight)
            #expect(height <= RegularHomeHeroLayout.posterMaxHeight)
        }
    }

    @Test("the poster keeps the cover's own 3:4 ratio")
    func posterKeepsCoverRatio() {
        let hero: CGFloat = 700
        let width = RegularHomeHeroLayout.posterWidth(heroHeight: hero)
        let height = RegularHomeHeroLayout.posterHeight(heroHeight: hero)
        #expect(abs(width / height - 3.0 / 4.0) < 0.0001)
        #expect(width < height)
    }

    @Test("text and poster never overlap on a wide window")
    func textLeavesRoomForThePoster() {
        let width: CGFloat = 1200
        let hero = RegularHomeHeroLayout.contentHeight(viewportHeight: 800)
        #expect(RegularHomeHeroLayout.showsPoster(width: width))
        let text = RegularHomeHeroLayout.textWidth(width: width, heroHeight: hero)
        let used = text
            + RegularHomeHeroLayout.posterWidth(heroHeight: hero)
            + RegularHomeHeroLayout.posterGap
            + RegularHomeHeroLayout.horizontalPadding * 2
        #expect(used <= width + 0.001)
    }

    @Test("a narrow window drops the poster and gives the width back to the text")
    func narrowWindowDropsThePoster() {
        let width = RegularHomeHeroLayout.posterMinimumWindowWidth - 1
        #expect(!RegularHomeHeroLayout.showsPoster(width: width))
        let hero = RegularHomeHeroLayout.contentHeight(viewportHeight: 700)
        let narrow = RegularHomeHeroLayout.textWidth(width: width, heroHeight: hero)
        let wide = RegularHomeHeroLayout.textWidth(
            width: RegularHomeHeroLayout.posterMinimumWindowWidth, heroHeight: hero
        )
        #expect(narrow > wide)
    }

    @Test("text width never collapses, even in a degenerate window")
    func textWidthHasAFloor() {
        #expect(RegularHomeHeroLayout.textWidth(width: 0, heroHeight: 0) >= 240)
        #expect(RegularHomeHeroLayout.textWidth(width: 950, heroHeight: 4000) >= 240)
    }

    @Test("autoplay walks forward and wraps at the end")
    func autoplayWraps() {
        #expect(RegularHomeHeroLayout.nextIndex(current: 0, count: 5) == 1)
        #expect(RegularHomeHeroLayout.nextIndex(current: 3, count: 5) == 4)
        #expect(RegularHomeHeroLayout.nextIndex(current: 4, count: 5) == 0)
    }

    @Test("autoplay stays put when there is nothing to advance to")
    func autoplayNoOps() {
        #expect(RegularHomeHeroLayout.nextIndex(current: 0, count: 1) == 0)
        #expect(RegularHomeHeroLayout.nextIndex(current: 0, count: 0) == 0)
        // 索引脏了（列表缩短过）也不能越界
        #expect(RegularHomeHeroLayout.nextIndex(current: 99, count: 3) == 0)
        #expect(RegularHomeHeroLayout.nextIndex(current: -4, count: 3) == 1)
    }

    @Test("episode count is read from the info string, never invented")
    func episodeCountParsing() {
        #expect(RegularHomeHeroLayout.episodeCountText(fromInfo: "14话 / 2026年7月4日 / 导演")
            == "14 集")
        #expect(RegularHomeHeroLayout.episodeCountText(fromInfo: "全 26话") == "26 集")
        // 没有话数就什么都不显示，不能编一个出来
        #expect(RegularHomeHeroLayout.episodeCountText(fromInfo: "2026年7月4日 / 导演") == nil)
        #expect(RegularHomeHeroLayout.episodeCountText(fromInfo: "") == nil)
    }

    @Test("the latin title is dropped when it just repeats the displayed one")
    func latinTitleDeduplicates() {
        #expect(RegularHomeHeroLayout.latinTitle(
            for: item(id: 1, name: "SOUSOU NO FRIEREN", nameCn: "")
        ) == nil)
        #expect(RegularHomeHeroLayout.latinTitle(
            for: item(id: 2, name: "SOUSOU NO FRIEREN", nameCn: "葬送的芙莉莲")
        ) == "SOUSOU NO FRIEREN")
        #expect(RegularHomeHeroLayout.latinTitle(
            for: item(id: 3, name: "   ", nameCn: "葬送的芙莉莲")
        ) == nil)
    }

    @Test("the ambient glow reaches past the window edge but stays a tint")
    func glowCoversTheHero() {
        // 光晕半径按窗宽算，必须够大才不会在角上切出一道边。
        #expect(RegularHomeHeroLayout.glowRadiusRatio >= 0.8)
        #expect(RegularHomeHeroLayout.glowOpacity > 0)
        // 它只负责收拢色调；盖过模糊底就又变回一块纯渐变色块了。
        #expect(RegularHomeHeroLayout.glowOpacity < 0.4)
        #expect(RegularHomeHeroLayout.counterGlowOpacity < RegularHomeHeroLayout.glowOpacity)
    }

    @Test("the backdrop blurs away the pixels while keeping the cover recognisable")
    func backdropBlurIsCalibrated() {
        // 太小会露出低分辨率的马赛克，太大就糊成纯色块、看不出是这张封面。
        #expect(RegularHomeHeroLayout.backdropBlurRadius >= 16)
        #expect(RegularHomeHeroLayout.backdropBlurRadius <= 40)
        // 模糊把边缘吸淡，必须超铺一圈盖住
        #expect(RegularHomeHeroLayout.backdropOverscan > 1)
        #expect(RegularHomeHeroLayout.backdropDim > 0)
        #expect(RegularHomeHeroLayout.backdropDim < 1)
    }

    @Test("quick-switch thumbs keep the cover ratio at both sizes")
    func switchThumbKeepsRatio() {
        for hero in [CGFloat(520), 900] {
            #expect(
                abs(RegularHomeHeroLayout.switchThumbWidth(heroHeight: hero)
                    / RegularHomeHeroLayout.switchThumbHeight(heroHeight: hero)
                    - 3.0 / 4.0) < 0.0001
            )
        }
    }

    @Test("a short window degrades instead of pushing content under the top bar")
    func shortWindowDegrades() {
        // 视口 650 的窗口：hero = 650 - 132 = 518，被抬到下限。
        let hero = RegularHomeHeroLayout.contentHeight(viewportHeight: 650)
        #expect(hero == RegularHomeHeroLayout.minHeight)
        #expect(RegularHomeHeroLayout.isCompact(heroHeight: hero))
        // 精简版：标题更小、缩略图更小
        #expect(RegularHomeHeroLayout.titleSize(heroHeight: hero)
            < RegularHomeHeroLayout.titleSize(heroHeight: 900))
        #expect(RegularHomeHeroLayout.switchThumbHeight(heroHeight: hero)
            < RegularHomeHeroLayout.switchThumbHeight(heroHeight: 900))
    }

    @Test("a tall window keeps the full layout")
    func tallWindowKeepsEverything() {
        let hero = RegularHomeHeroLayout.contentHeight(viewportHeight: 900)
        #expect(!RegularHomeHeroLayout.isCompact(heroHeight: hero))
        #expect(RegularHomeHeroLayout.switchThumbHeight(heroHeight: hero)
            == RegularHomeHeroLayout.switchThumbHeight)
    }

    @Test("the height floor leaves room for the top bar plus the compact column")
    func heightFloorClearsTheTopBar() {
        // 下限必须容得下顶栏让位 + 精简版内容，否则内容会被顶栏盖住。
        #expect(
            RegularHomeHeroLayout.minHeight
                > RegularShellLayout.contentTopInset(for: .belowSafeArea) + 380
        )
        #expect(RegularHomeHeroLayout.minHeight < RegularHomeHeroLayout.compactThreshold)
    }

    @Test("the meta block stays narrow enough to read")
    func metaBlockIsNarrow() {
        #expect(RegularHomeHeroLayout.metaMaxWidth < 900)
        #expect(RegularHomeHeroLayout.horizontalPadding
            > HomeHeroBannerLayout.horizontalPadding)
    }
}
