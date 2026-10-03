import SwiftData
import SwiftUI

/// Cezzu App 的根视图。两个 App target（iOS / macOS）都把它作为 entry。
///
/// 按 `horizontalSizeClass` 分壳：
/// - compact（iPhone）→ `CompactRootView` + 窄屏页（`HomeView` / `SearchView` / `DetailView`）
/// - regular（iPad / Mac）→ `RegularShellView` + 宽屏页（`RegularHomeView` / `RegularSearchView` / `RegularDetailView`）
///
/// 宽窄屏首页 / 搜索 / 详情 **分开维护**，不再用同一套自适应布局。
public struct CezzuRoot: View {
    /// 外部传入的 session（macOS 多窗口场景）。不能放进 @State，否则 App 侧替换 session 时
    /// Root 会继续持有旧的 empty fallback，导致规则/历史永远不加载。
    private let externalSession: CezzuSession?
    @State private var ownedSession: CezzuSession = .empty()
    @State private var didInitializePersistentSession: Bool = false

    /// 默认构造：内部自己创建空 session 并在 task 里初始化持久化容器（iOS / 正常单窗口路径）。
    public init() {
        self.externalSession = nil
    }

    /// 外部传入 session（主要用于 macOS App 持有 session 并同时支持独立播放器窗口）。
    /// 调用方负责创建/替换 session；CezzuRoot 只读取，不再复制到自己的 @State。
    public init(session: CezzuSession) {
        self.externalSession = session
    }

    private var session: CezzuSession {
        externalSession ?? ownedSession
    }

    public var body: some View {
        CezzuRootContent(session: session)
            .environment(session.store)
            .environment(session.history)
            .environment(session.followStore)
            .environment(session.searchHistory)
            .task {
                // 外部 session 由 App 持有并初始化，这里不要再碰。
                guard externalSession == nil else { return }
                guard !didInitializePersistentSession else { return }
                didInitializePersistentSession = true
                await initializeOwned()
            }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    @MainActor
    private func initializeOwned() async {
        ownedSession = await CezzuSession.makePersistent()
    }
}

/// 一次启动会话的状态束 —— 在 `CezzuRoot` 完成初始化之后用 `Environment` 注入。
@MainActor
@Observable
public final class CezzuSession {
    public let store: RuleStoreCoordinator
    public let history: HistoryStore
    public let followStore: FollowStore
    public let searchHistory: SearchHistoryStore
    public let container: ModelContainer?
    public let bangumiAPI: BangumiAPIClientProtocol
    public let shouldBootstrapAtLaunch: Bool

    public init(
        store: RuleStoreCoordinator,
        history: HistoryStore,
        followStore: FollowStore,
        searchHistory: SearchHistoryStore,
        container: ModelContainer?,
        bangumiAPI: BangumiAPIClientProtocol = BangumiAPIClient.shared,
        shouldBootstrapAtLaunch: Bool = true
    ) {
        self.store = store
        self.history = history
        self.followStore = followStore
        self.searchHistory = searchHistory
        self.container = container
        self.bangumiAPI = bangumiAPI
        self.shouldBootstrapAtLaunch = shouldBootstrapAtLaunch
    }

    public static func empty() -> CezzuSession {
        // 用一个 in-memory 的 fallback container 兜底，避免 Crash
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(
            for: WatchHistoryEntry.self, FollowEntry.self, RuleSourceRecord.self,
            SearchHistoryEntry.self,
            configurations: config
        ) else {
            preconditionFailure("failed to create in-memory ModelContainer for CezzuSession.empty()")
        }
        let context = container.mainContext
        let sourceStore = RuleSourceStore(context: context)
        let store = RuleStoreCoordinator(sourceStore: sourceStore)
        let history = HistoryStore(context: context)
        let followStore = FollowStore(context: context)
        let searchHistory = SearchHistoryStore(context: context)
        return CezzuSession(
            store: store,
            history: history,
            followStore: followStore,
            searchHistory: searchHistory,
            container: container,
            shouldBootstrapAtLaunch: false
        )
    }

    /// 创建实际的持久化 session（用于 macOS 独立窗口等多窗口场景）。
    /// 调用方需要在 @MainActor 上异步调用，并把结果传入 CezzuRoot 或直接注入环境。
    public static func makePersistent() async -> CezzuSession {
        do {
            let container = try ModelContainer(
                for: WatchHistoryEntry.self, FollowEntry.self, RuleSourceRecord.self,
                SearchHistoryEntry.self
            )
            let context = container.mainContext
            let sourceStore = RuleSourceStore(context: context)
            let store = RuleStoreCoordinator(sourceStore: sourceStore)
            let history = HistoryStore(context: context)
            let followStore = FollowStore(context: context)
            let searchHistory = SearchHistoryStore(context: context)
            return CezzuSession(
                store: store,
                history: history,
                followStore: followStore,
                searchHistory: searchHistory,
                container: container,
                shouldBootstrapAtLaunch: true
            )
        } catch {
            // 失败时回退到内存版，保持 App 可用
            return .empty()
        }
    }
}

/// 真正的根 UI（已经拿到 session 后）。在内部根据 size class 切换窄屏 dock 外壳 /
/// 宽屏沉浸式外壳，但所有 view model 共享同一个 session。
struct CezzuRootContent: View {
    let session: CezzuSession

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
                if sizeClass == .compact {
                    CompactRootView(session: session)
                } else {
                    RegularShellView(session: session)
                }
            #else
                RegularShellView(session: session)
            #endif
        }
        .task(id: ObjectIdentifier(session.store)) {
            guard session.shouldBootstrapAtLaunch else { return }
            await session.store.bootstrap()
        }
    }
}

// MARK: - iPhone 外壳

/// iPhone 底部 dock 的一级入口。
///
/// 搜索不在 dock 里 —— 它是首页右上角的入口，push 进同一条导航栈。
enum CompactTab: Hashable, CaseIterable {
    case home, follow, settings

    /// dock 上不摆文字，标题只给读屏用。
    var label: String {
        switch self {
        case .home: return "主页"
        case .follow: return "追番"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "play.rectangle"
        case .follow: return "star"
        case .settings: return "gearshape"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .follow: return "star.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// 这个 tab 的页面是不是恒定深色底。是的话 dock 和导航栏要按深色上下文渲染，
    /// 否则浅色模式下玻璃虽然被底下的黑透暗了，icon 仍按浅色算成黑的，糊成一片。
    var prefersDarkChrome: Bool {
        switch self {
        case .home: return true
        case .follow, .settings: return false
        }
    }
}

struct CompactRootView: View {
    let session: CezzuSession
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.colorScheme) private var systemScheme
    /// 用具体的 `[Route]` 而不是 `NavigationPath` —— dock 的明暗要读栈顶是哪一页。
    @State private var path: [Route] = []
    @State private var selectedTab: CompactTab = .home
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel
    @State private var activePlayerRequest: PlaybackRequest?
    @State private var activeSourceCache: SourceSearchCache?
    @State private var playerTransitionVisible: Bool = false

    init(session: CezzuSession) {
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
        ZStack {
            compactTabView
                .environment(\.colorScheme, dockScheme)
                .scaleEffect(playerTransitionVisible ? 0.985 : 1)
                .opacity(playerTransitionVisible ? 0.92 : 1)
                .blur(radius: playerTransitionVisible ? 4 : 0)
                .disabled(activePlayerRequest != nil)
                .animation(.easeInOut(duration: 0.22), value: playerTransitionVisible)

            if let activePlayerRequest {
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                        .opacity(playerTransitionVisible ? 1 : 0)

                    PlayerView(
                        request: activePlayerRequest,
                        coordinator: PlaybackCoordinator(history: session.history),
                        history: session.history,
                        sourceCache: activeSourceCache,
                        onClose: dismissPlayer
                    )
                    .opacity(playerTransitionVisible ? 1 : 0)
                    .scaleEffect(playerTransitionVisible ? 1 : 1.03)
                }
                // 安全区交给 PlayerView 自己处理：横屏 / 宽屏铺满，竖屏要给状态栏留位。
                .transition(.identity)
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.92), value: activePlayerRequest != nil)
        // iOS 先 empty session 出 UI，再换 persistent：@State searchModel 不会随 session 重建，
        // 必须把 history 绑到新 store，否则搜索历史只写内存，且旧 container 释放后会闪退。
        .onChange(of: ObjectIdentifier(session.searchHistory)) { _, _ in
            searchModel.bindHistory(session.searchHistory)
        }
    }

    /// 三个入口，只留图标不留文字 —— 系统 dock 因此收成窄窄一条居中的胶囊。
    /// active 用实心 SF Symbol，非 active 用描边。
    ///
    /// dock 自己的明暗跟当前 tab 走：首页恒定深色底，dock 要按深色渲染才看得清 icon；
    /// 追番 / 设置跟随系统。各 tab 的内容再把 scheme 拨回系统值，
    /// 免得这层 chrome 用的深色顺着导航栈漏进详情页。
    private var dockScheme: ColorScheme {
        // 设置页有自己的导航栈，共享的 path 跟它无关。
        guard selectedTab != .settings else { return systemScheme }
        let dark = path.last?.prefersDarkChrome ?? selectedTab.prefersDarkChrome
        return dark ? .dark : systemScheme
    }

    @ViewBuilder
    private var compactTabView: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            TabView(selection: $selectedTab) {
                Tab(value: .home) {
                    homeStack
                } label: {
                    dockLabel(.home)
                }

                Tab(value: .follow) {
                    followStack
                } label: {
                    dockLabel(.follow)
                }

                Tab(value: .settings) {
                    settingsStack
                } label: {
                    dockLabel(.settings)
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                homeStack
                    .tabItem { dockLabel(.home) }
                    .tag(CompactTab.home)

                followStack
                    .tabItem { dockLabel(.follow) }
                    .tag(CompactTab.follow)

                settingsStack
                    .tabItem { dockLabel(.settings) }
                    .tag(CompactTab.settings)
            }
        }
    }

    /// 只给图标不给 `Text`，dock 就不摆文字了；标题留给读屏。
    /// 同时关掉 Tab 系统默认的 fill 变体注入。
    private func dockLabel(_ tab: CompactTab) -> some View {
        let isActive = selectedTab == tab
        return Image(systemName: isActive ? tab.selectedSystemImage : tab.systemImage)
            .environment(\.symbolVariants, isActive ? .fill : SymbolVariants.none)
            .accessibilityLabel(tab.label)
    }

    private var homeStack: some View {
        NavigationStack(path: $path) {
            HomeView(
                model: homeModel,
                history: session.history,
                onTapItem: { item in
                    path.append(Route.detail(item))
                },
                onTapSection: { section in
                    path.append(Route.tagSection(tag: section.tag))
                },
                onTapHistoryEntry: { entry in
                    path.append(Route.historyDetail(historyHint(from: entry)))
                },
                onRemoveHistoryEntry: { entry in
                    try? session.history.delete(entry)
                },
                onTapSearch: {
                    path.append(Route.search)
                }
            )
            .navigationDestination(for: Route.self) { route in
                routeView(route)
            }
        }
        .environment(\.colorScheme, systemScheme)
    }

    private var followStack: some View {
        NavigationStack(path: $path) {
            FollowView(followStore: session.followStore) { item in
                path.append(Route.detail(item))
            }
            .navigationDestination(for: Route.self) { route in
                routeView(route)
            }
        }
        .environment(\.colorScheme, systemScheme)
    }

    private var settingsStack: some View {
        NavigationStack {
            SettingsView()
        }
        .environment(\.colorScheme, systemScheme)
    }

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .home:
            HomeView(
                model: homeModel,
                history: session.history,
                onTapItem: { item in path.append(Route.detail(item)) },
                onTapSection: { section in path.append(Route.tagSection(tag: section.tag)) },
                onTapHistoryEntry: { entry in
                    path.append(Route.historyDetail(historyHint(from: entry)))
                },
                onRemoveHistoryEntry: { entry in
                    try? session.history.delete(entry)
                },
                onTapSearch: { path.append(Route.search) }
            )
        case .search:
            SearchView(
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
            DetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: historyEntry.map(historyHint(from:))
                )
            ) { request, cache in
                activeSourceCache = cache
                presentPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .historyDetail(let hint):
            DetailView(
                model: DetailViewModel(
                    item: hint.item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: hint
                )
            ) { request, cache in
                activeSourceCache = cache
                presentPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    presentPlayer(req)
                }
            }
        case .player(let req):
            Color.clear
                .task {
                    guard activePlayerRequest == nil else { return }
                    if !path.isEmpty {
                        path.removeLast()
                    }
                    presentPlayer(req)
                }
        case .ruleManager, .ruleSources:
            RuleManagerView(store: session.store)
        case .settings:
            SettingsView()
        case .follow:
            FollowView(followStore: session.followStore) { item in
                path.append(Route.detail(item))
            }
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

    private func presentPlayer(_ request: PlaybackRequest) {
        guard activePlayerRequest == nil else { return }

        activePlayerRequest = request
        withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) {
            playerTransitionVisible = true
        }
    }

    private func dismissPlayer() {
        withAnimation(.easeInOut(duration: 0.2)) {
            playerTransitionVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            activePlayerRequest = nil
            activeSourceCache = nil
        }
    }
}
