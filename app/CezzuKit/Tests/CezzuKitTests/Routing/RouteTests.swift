import Testing
@testable import CezzuKit

@Suite("Route")
struct RouteTests {

    private var sampleItem: BangumiItem {
        BangumiItem(
            id: 1,
            name: "name",
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

    /// 强制影院深色底的那几页 —— dock / 导航栏要按深色渲染才看得清 icon。
    @Test("the cinema-dark destinations ask for dark chrome")
    func darkDestinations() {
        #expect(Route.home.prefersDarkChrome)
        #expect(Route.search.prefersDarkChrome)
    }

    /// 从首页 push 出来的页面跟随系统。dock 要是还停在深色，
    /// 浅色模式下就是白 icon 压浅玻璃 —— 正是要修的那个 bug。
    @Test("destinations pushed off the home stack follow the system instead")
    func pushedDestinationsAreNotDark() {
        #expect(!Route.tagSection(tag: "").prefersDarkChrome)
        #expect(!Route.tagSection(tag: "anime").prefersDarkChrome)
        #expect(!Route.detail(sampleItem).prefersDarkChrome)
        #expect(!Route.follow.prefersDarkChrome)
        #expect(!Route.settings.prefersDarkChrome)
        #expect(!Route.ruleManager.prefersDarkChrome)
        #expect(!Route.ruleSources.prefersDarkChrome)
    }
}
