import SwiftUI

/// 宽屏（macOS / iPad）外壳 —— 没有 sidebar、没有 dock。
///
/// 一级入口做成悬浮在内容之上的顶栏（`RegularTopBar`），首页的全幅 banner 直接
/// 铺到窗口最上沿从它下面穿过去，整壳强制深色，要的就是影院里那种"只有画面"的感觉。
/// 二级页（详情 / 分区 / 搜索结果）仍然走 `NavigationStack`，返回交给系统。
struct RegularShellView: View {
    let session: TubeSession
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.openWindow) private var openWindow
    @State private var pages = RegularShellPages()
    @State private var path: [Route] = []
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel
    /// 播放器进入沉浸模式时把顶栏也收起来。
    @State private var chromeHidden: Bool = false
    @Environment(\.regularTopBarPlacement) private var topBarPlacement

    init(session: TubeSession) {
        self.session = session
        self._searchModel = State(
            initialValue: SearchViewModel(
                api: session.bangumiAPI,
                history: session.searchHistory
            )
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
        Group {
            if let playerRequest = activePlayerRequest {
                standalonePlayer(for: playerRequest)
            } else {
                shell
            }
        }
        // 与 CompactRootView 相同：session 从 empty 升级到 persistent 时重绑搜索历史 store。
        .onChange(of: ObjectIdentifier(session.searchHistory)) { _, _ in
            searchModel.bindHistory(session.searchHistory)
        }
    }

    private var activePlayerRequest: PlaybackRequest? {
        // macOS 独立窗口模式下，永远不让主窗口走“替换整个 UI”的播放器路径。
        if presentation.prefersDedicatedWindow { return nil }
        guard case .player(let request) = path.last else { return nil }
        return request
    }

    /// 顶栏只在一级页出现；push 进二级页之后交给系统返回按钮，避免两套返回打架。
    private var showsTopBar: Bool {
        path.isEmpty && !chromeHidden
    }

    @ViewBuilder
    private var shell: some View {
        ZStack(alignment: .top) {
            RegularShellLayout.cinemaBackground
                .ignoresSafeArea()

            NavigationStack(path: $path) {
                rootContent
                    .navigationDestination(for: Route.self) { route in
                        navigationDestination(for: route)
                    }
            }

            Group {
                if showsTopBar {
                    RegularTopBar(selected: pages.current) { selected in
                        // 不给切页上过渡动画：两棵重页面同时在场插值一遍，
                        // 切换就卡在那 0.22 秒里。
                        path.removeAll()
                        pages.select(selected)
                    }
                    .transition(.opacity)
                }
            }
            // 只让顶栏自己淡入淡出；挂在 ZStack 上会把整条导航栈一起卷进动画。
            .animation(.easeInOut(duration: 0.22), value: showsTopBar)
        }
        .environment(\.colorScheme, .dark)
        .environment(
            \.playerChromeController,
            PlayerChromeController { hidden in
                withAnimation(.easeInOut(duration: 0.25)) { chromeHidden = hidden }
            }
        )
    }

    private func standalonePlayer(for request: PlaybackRequest) -> some View {
        PlayerView(
            request: request,
            coordinator: PlaybackCoordinator(
                history: session.history,
                progressTracker: session.collections
            ),
            history: session.history,
            onClose: {
                guard !path.isEmpty else { return }
                path.removeLast()
            }
        )
    }

    // MARK: - 一级页

    /// 访问过的一级页全留在树里，切换只是换谁露出来 —— 重铺一整页的代价只在首次进入付一次。
    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            ForEach(RegularShellTab.allCases) { entry in
                if pages.visited.contains(entry) {
                    page(entry)
                        .opacity(pages.isActive(entry) ? 1 : 0)
                        .allowsHitTesting(pages.isActive(entry))
                        .accessibilityHidden(!pages.isActive(entry))
                        .zIndex(pages.isActive(entry) ? 1 : 0)
                        .environment(\.regularShellPageIsActive, pages.isActive(entry))
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ entry: RegularShellTab) -> some View {
        switch entry {
        case .home:
            homeView
        case .follow:
            RegularFollowView(followStore: session.followStore) { item in
                path.append(Route.detail(item))
            }
        case .search:
            underTopBar {
                RegularSearchView(
                    model: searchModel,
                    browseModel: homeModel,
                    onTapItem: { item in path.append(Route.detail(item)) },
                    onTapSection: { section in path.append(Route.tagSection(tag: section.tag)) }
                )
            }
        case .settings:
            underTopBar {
                SettingsView()
            }
            // 换代 = 把设置页连同它压上去的二级页一起拆掉，见 `RegularShellPages`。
            .id(pages.settingsGeneration)
        }
    }

    private var homeView: some View {
        RegularHomeView(
            model: homeModel,
            history: session.history,
            onTapItem: { item in path.append(Route.detail(item)) },
            onTapSection: { section in path.append(Route.tagSection(tag: section.tag)) },
            onTapHistoryEntry: { entry in
                path.append(Route.historyDetail(historyHint(from: entry)))
            },
            onRemoveHistoryEntry: { entry in
                try? session.history.delete(entry)
            }
        )
    }

    /// 非首页的一级页不铺到顶栏下面，让出顶栏高度即可。
    @ViewBuilder
    private func underTopBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .safeAreaInset(edge: .top) {
                Color.clear.frame(
                    height: RegularShellLayout.contentTopInset(for: topBarPlacement)
                )
            }
            .background(RegularShellLayout.cinemaBackground)
    }

    // MARK: - 二级页

    /// 二级页必须自己带一层不透明底 —— NavigationStack 把 root（首页）留在视图树里，
    /// destination 只是盖在上面；destination 一透明，首页就从底下透出来跟它叠在一起。
    @ViewBuilder
    private func navigationDestination(for route: Route) -> some View {
        destinationContent(for: route)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RegularShellLayout.cinemaBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func destinationContent(for route: Route) -> some View {
        switch route {
        case .home:
            homeView
        case .search:
            RegularSearchView(
                model: searchModel,
                browseModel: homeModel,
                onTapItem: { item in path.append(Route.detail(item)) },
                onTapSection: { section in path.append(Route.tagSection(tag: section.tag)) }
            )
        case .tagSection(let tag):
            TagSectionView(
                api: session.bangumiAPI,
                tag: tag,
                onTapItem: { item in path.append(Route.detail(item)) }
            )
        case .detail(let item):
            let historyEntry = try? session.history.entry(forBangumiItem: item)
            RegularDetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: historyEntry.map(historyHint(from:))
                )
            ) { request, _ in
                launchPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .historyDetail(let hint):
            RegularDetailView(
                model: DetailViewModel(
                    item: hint.item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: hint
                )
            ) { request, _ in
                launchPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    launchPlayer(req)
                }
            }
        case .player(let req):
            if presentation.prefersDedicatedWindow {
                // Deep link 或残留 route：打开独立窗口，并清理主窗口的播放器 route
                Color.clear
                    .task {
                        openWindow(id: "player", value: req)
                        // 延迟一帧清理，避免导航状态竞争
                        try? await Task.sleep(for: .milliseconds(50))
                        if case .player = path.last {
                            path.removeLast()
                        }
                    }
            } else {
                PlayerView(
                    request: req,
                    coordinator: PlaybackCoordinator(
                history: session.history,
                progressTracker: session.collections
            ),
                    history: session.history
                )
            }
        default:
            EmptyView()
        }
    }

    private func historyHint(from entry: WatchHistoryEntry) -> HistoryResumeHint {
        HistoryResumeHint(
            bangumiTitle: entry.bangumiTitle,
            coverURLString: entry.coverURLString,
            detailURL: URL(string: entry.detailURLString) ?? URL(string: "https://invalid.local")!,
            ruleName: entry.ruleName,
            episodeIndex: entry.lastEpisodeIndex,
            episodeTitle: entry.lastEpisodeTitle,
            positionMs: entry.lastPositionMs,
            subjectID: entry.subjectID
        )
    }

    /// 根据当前 presentation 模式决定是打开独立播放器窗口还是在当前导航栈 push。
    /// macOS 独立窗口模式下不会修改主窗口的 path，详情页保持可见。
    private func launchPlayer(_ request: PlaybackRequest) {
        if presentation.prefersDedicatedWindow {
            openWindow(id: "player", value: request)
        } else {
            path.append(Route.player(request))
        }
    }
}
