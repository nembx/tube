import Foundation
import Observation

/// 两个外壳（窄屏 dock / 宽屏影院）共用的会话内 UI 状态与视图模型。
///
/// 存在的理由：iPhone Duo 一开一合，`horizontalSizeClass` 就在 compact / regular
/// 之间翻，`TubeRootContent` 随之整个换壳。这些状态若留在壳自己的 `@State` 里，
/// 合上盖子就等于回到首页 —— 导航栈清空、首页分区和搜索结果全部重建重拉，
/// 正在看的那一页一折就没了。iPad 分屏从宽拖窄也是同一回事。
/// 状态提到壳之上，换壳只是换一副皮。
@MainActor
@Observable
final class ShellState {
    /// 两个壳共用同一条 `Route` 栈。用具体的 `[Route]` 而不是 `NavigationPath` ——
    /// dock 的明暗要读栈顶是哪一页。
    var path: [Route] = []
    /// 一级入口。以宽屏的四个（home / follow / search / settings）为准存着，
    /// 窄屏没有搜索入口，换壳时由 `ShellHandoff` 把搜索折进首页栈。
    var pages = RegularShellPages()
    let searchModel: SearchViewModel
    let homeModel: HomeViewModel
    /// 窄屏用整屏覆盖层呈现的播放请求；宽屏把 `.player` 放进 `path`。
    /// 折到窄屏时 `.player` route 会被翻成这个，展开时宽屏也直接接住它。
    var activePlayerRequest: PlaybackRequest?
    var activeSourceCache: SourceSearchCache?

    init(session: TubeSession) {
        self.searchModel = SearchViewModel(
            api: session.bangumiAPI,
            history: session.searchHistory
        )
        self.homeModel = HomeViewModel(api: session.bangumiAPI)
    }
}

/// 换壳时的状态翻译。
///
/// 窄屏把搜索页放在首页导航栈里（`path` 的第一层），宽屏的搜索是一级入口
/// （`pages.current == .search`）。开合屏时把这两种说法互相翻译一下，
/// 用户看到的还是同一页；栈上更深的页（详情 / 分区）原样保留。
enum ShellHandoff {
    /// 进入窄屏壳：一级入口上的搜索页落回首页栈的第一层。
    static func enteringCompact(
        path: [Route],
        pages: RegularShellPages
    ) -> (path: [Route], pages: RegularShellPages) {
        guard pages.current == .search else { return (path, pages) }
        var pages = pages
        pages.select(.home)
        var path = path
        if path.first != .search {
            path.insert(.search, at: 0)
        }
        return (path, pages)
    }

    /// 进入宽屏壳：首页栈第一层的搜索页重新变回一级入口。
    static func enteringRegular(
        path: [Route],
        pages: RegularShellPages
    ) -> (path: [Route], pages: RegularShellPages) {
        guard path.first == .search else { return (path, pages) }
        var pages = pages
        pages.select(.search)
        var path = path
        path.removeFirst()
        return (path, pages)
    }
}
