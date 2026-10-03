import Testing
@testable import CezzuKit

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
}
