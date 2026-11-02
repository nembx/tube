import Testing
@testable import TubeKit

@Suite("CompactTab")
struct CompactTabTests {

    /// 搜索已经挪到首页右上角，dock 里只剩三个入口。
    @Test("the dock carries exactly the three primary entries")
    func dockHasThreeEntries() {
        #expect(CompactTab.allCases == [.home, .follow, .settings])
    }

    /// dock 上不摆文字，但标题不能空 —— 那是读屏唯一能念的东西。
    @Test("every entry has a label and both icon variants")
    func entriesAreComplete() {
        for tab in CompactTab.allCases {
            #expect(!tab.label.isEmpty)
            #expect(!tab.systemImage.isEmpty)
            #expect(!tab.selectedSystemImage.isEmpty)
        }
    }

    /// 首页恒定深色底，dock 得按深色渲染才看得清；其余两页跟随系统。
    @Test("only the constantly dark page asks for dark chrome")
    func onlyHomeAsksForDarkChrome() {
        #expect(CompactTab.home.prefersDarkChrome)
        #expect(!CompactTab.follow.prefersDarkChrome)
        #expect(!CompactTab.settings.prefersDarkChrome)
    }

    /// 一级入口以宽屏的四个为准存着；窄屏没有搜索入口，宽屏的搜索落到首页那颗 dock 上。
    @Test("dock entries round-trip through the wide-screen sections, search lands on home")
    func dockEntriesMapOntoSections() {
        for tab in CompactTab.allCases {
            #expect(CompactTab(section: tab.section) == tab)
        }
        #expect(CompactTab(section: .search) == .home)
    }

    /// 三条栈共用一条 path：切入口前不清栈，追番栈会顶着首页 push 的详情页出场，
    /// 看着像点了没反应，得再点一下才见到列表。
    @Test("switching to another entry clears the shared path")
    func switchingEntryClearsPath() {
        #expect(CompactTab.switchingClearsPath(from: .home, to: .follow))
        #expect(CompactTab.switchingClearsPath(from: .follow, to: .settings))
        #expect(CompactTab.switchingClearsPath(from: .settings, to: .home))
        #expect(CompactTab.switchingClearsPath(from: .search, to: .follow))
    }

    /// 同一入口重选交给系统弹回根；换壳时 TabView 回写当前选中项也不能把栈清掉，
    /// 宽屏的搜索在 dock 上就是首页，不算切页。
    @Test("reselecting the current entry keeps the path")
    func reselectingKeepsPath() {
        #expect(CompactTab.switchingClearsPath(from: .follow, to: .follow) == false)
        #expect(CompactTab.switchingClearsPath(from: .home, to: .home) == false)
        #expect(CompactTab.switchingClearsPath(from: .search, to: .home) == false)
    }
}
