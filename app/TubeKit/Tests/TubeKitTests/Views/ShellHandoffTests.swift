import Testing
@testable import TubeKit

/// 换壳（iPhone Duo 开合、iPad 分屏变窄）时搜索页在两种壳之间的翻译。
@Suite("ShellHandoff")
struct ShellHandoffTests {

    private static func pages(on tab: RegularShellTab) -> RegularShellPages {
        var pages = RegularShellPages()
        pages.select(tab)
        return pages
    }

    @Test("folding while on the wide-screen search page pushes search onto the home stack")
    func foldingMovesSearchIntoTheHomeStack() {
        let result = ShellHandoff.enteringCompact(
            path: [.tagSection(tag: "日常")],
            pages: Self.pages(on: .search)
        )
        #expect(result.pages.current == .home)
        // 搜索落到栈的第一层，正在看的分区页仍然压在上面。
        #expect(result.path == [.search, .tagSection(tag: "日常")])
    }

    @Test("folding on any other page leaves the stack alone")
    func foldingElsewhereIsANoOp() {
        let path: [Route] = [.tagSection(tag: "热血")]
        for tab in [RegularShellTab.home, .follow, .settings] {
            let result = ShellHandoff.enteringCompact(path: path, pages: Self.pages(on: tab))
            #expect(result.pages.current == tab)
            #expect(result.path == path)
        }
    }

    @Test("folding does not stack a second search page if one is already at the root")
    func foldingDoesNotDuplicateSearch() {
        let result = ShellHandoff.enteringCompact(
            path: [.search, .settings],
            pages: Self.pages(on: .search)
        )
        #expect(result.path == [.search, .settings])
        #expect(result.pages.current == .home)
    }

    @Test("unfolding turns a root-level search page back into the search section")
    func unfoldingPromotesSearchToASection() {
        let result = ShellHandoff.enteringRegular(
            path: [.search, .tagSection(tag: "治愈")],
            pages: Self.pages(on: .home)
        )
        #expect(result.pages.current == .search)
        #expect(result.path == [.tagSection(tag: "治愈")])
    }

    @Test("unfolding keeps the current section when search is not at the root")
    func unfoldingElsewhereIsANoOp() {
        let path: [Route] = [.tagSection(tag: "治愈"), .search]
        let result = ShellHandoff.enteringRegular(path: path, pages: Self.pages(on: .follow))
        #expect(result.pages.current == .follow)
        #expect(result.path == path)
    }

    @Test("a fold followed by an unfold lands back on the same page")
    func foldThenUnfoldRoundTrips() {
        let folded = ShellHandoff.enteringCompact(
            path: [.tagSection(tag: "校园")],
            pages: Self.pages(on: .search)
        )
        let unfolded = ShellHandoff.enteringRegular(path: folded.path, pages: folded.pages)
        #expect(unfolded.pages.current == .search)
        #expect(unfolded.path == [.tagSection(tag: "校园")])
    }
}
