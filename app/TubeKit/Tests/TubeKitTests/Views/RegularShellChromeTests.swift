import CoreGraphics
import Testing
@testable import TubeKit

@Suite("RegularShellChrome")
struct RegularShellChromeTests {

    @Test("the floating bar carries every top-level entry")
    func barCoversEveryEntry() {
        // 「最近观看」已并入首页的「继续观看」分区，不再单独占一个入口。
        let all = Set(RegularShellTab.allCases)
        #expect(all == [.home, .follow, .search, .settings])
    }

    @Test("search and settings sit at the trailing edge, everything else in the pill group")
    func searchAndSettingsAreNotPills() {
        #expect(RegularShellTab.primary == [.home, .follow])
        #expect(RegularShellTab.trailing == [.search, .settings])
    }

    /// 两组加起来必须正好是全部入口，且不重叠 —— 漏一个就是某个入口点不到了。
    @Test("the two groups partition every entry")
    func groupsPartitionEveryEntry() {
        let primary = Set(RegularShellTab.primary)
        let trailing = Set(RegularShellTab.trailing)
        #expect(primary.isDisjoint(with: trailing))
        #expect(primary.union(trailing) == Set(RegularShellTab.allCases))
    }

    @Test("every entry has a label and both icon variants")
    func entriesAreComplete() {
        for tab in RegularShellTab.allCases {
            #expect(!tab.label.isEmpty)
            #expect(!tab.systemImage.isEmpty)
            #expect(!tab.selectedSystemImage.isEmpty)
        }
    }

    /// 带整幅头图的入口才铺到顶栏下面；搜索和设置铺过去会把控件顶到顶栏底下。
    @Test("only the pages with a full-bleed header run under the floating bar")
    func onlyHeaderPagesExtendUnderTheBar() {
        for tab in RegularShellTab.allCases {
            #expect(tab.extendsUnderTopBar == (tab == .home || tab == .follow))
        }
        #expect(!RegularShellTab.search.extendsUnderTopBar)
        #expect(!RegularShellTab.settings.extendsUnderTopBar)
    }

    @Test("pages that do not extend under the bar reserve more than its height")
    func contentInsetClearsTheBar() {
        let inset = RegularShellLayout.contentTopInset(for: .belowSafeArea)
        #expect(inset > RegularShellLayout.barHeight)
        #expect(RegularShellLayout.scrimHeight > inset)
    }

    /// 顶栏升进标题栏那一条时，安全区本身已经把内容推下去了；再让一次会多出一块空白。
    @Test("in-title-bar placement reserves no extra content inset")
    func titleBarPlacementReservesNothing() {
        #expect(RegularShellLayout.contentTopInset(for: .inTitleBar) == 0)
    }

    @Test("the bar clears the window controls on the leading edge")
    func barClearsWindowControls() {
        // macOS 交通灯大约占到 x≈78，顶栏内容不能压上去。
        #expect(RegularShellLayout.barLeadingInset >= 78)
    }

    // MARK: - 一级页状态

    @Test("visited entries accumulate so pages can stay alive")
    func visitedEntriesAccumulate() {
        var pages = RegularShellPages()
        // 没进过的入口先不建，首页除外 —— 它是落地页。
        #expect(pages.visited == [.home])

        pages.select(.search)
        #expect(pages.current == .search)
        #expect(pages.visited == [.home, .search])
        #expect(pages.isActive(.search))
        #expect(!pages.isActive(.home))

        pages.select(.home)
        #expect(pages.visited == [.home, .search])
    }

    /// 设置页的二级页是 NavigationLink 直接压上去的，不进 path，只能靠换代拆掉。
    @Test("leaving, entering or re-tapping settings bumps its generation")
    func settingsGenerationTracksItsEntry() {
        var pages = RegularShellPages()
        let fresh = pages.settingsGeneration

        pages.select(.settings)
        let entered = pages.settingsGeneration
        #expect(entered != fresh)

        pages.select(.settings)
        let retapped = pages.settingsGeneration
        #expect(retapped != entered)

        pages.select(.home)
        #expect(pages.settingsGeneration != retapped)
    }

    /// 主页 / 搜索之间来回切不该动设置页 —— 它得原样留着，不然白重建。
    @Test("switching between other entries leaves settings untouched")
    func otherEntriesDoNotBumpSettings() {
        var pages = RegularShellPages()
        pages.select(.search)
        let generation = pages.settingsGeneration
        pages.select(.home)
        pages.select(.follow)
        #expect(pages.settingsGeneration == generation)
    }
}
