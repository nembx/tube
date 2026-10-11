import AVKit
import Observation
import SwiftUI

/// 播放屏：`AVPlayerLayer` 内嵌 + 自定义悬浮控制层 + 沉浸模式。
public struct PlayerView: View {
    @AppStorage(PlaybackSettings.enableDanmakuKey) private var enableDanmaku: Bool =
        PlaybackSettings.enableDanmakuDefault
    @AppStorage(PlaybackSettings.superResolutionModeKey) private var superResolutionRawMode: String =
        PlaybackSettings.superResolutionModeDefault.rawValue
    @State private var coordinator: PlaybackCoordinator
    @State private var activeRequest: PlaybackRequest
    @State private var danmakuController = PlayerDanmakuController()
    @State private var pictureInPictureController = PlayerPictureInPictureController()
    @State private var superResolutionDiagnostics = SuperResolutionDiagnosticsBridge()
    @State private var detailModel: PlayerDetailModel?
    public let request: PlaybackRequest
    public let history: HistoryStore?
    public let sourceCache: SourceSearchCache?
    private let onClose: (() -> Void)?

    @Environment(RuleStoreCoordinator.self) private var ruleStore
    @Environment(\.playerChromeController) private var chrome
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.playerPictureInPictureController) private var pictureInPicture
    @Environment(\.playerSystemPlaybackController) private var systemPlayback
    @Environment(\.playerInteractionController) private var interaction
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.playerCursorController) private var cursor
    @Environment(\.dismiss) private var dismiss

    @State private var showResumePrompt: Bool = false
    @State private var isImmersive: Bool = false
    @State private var controlsVisible: Bool = false
    /// 宽屏右侧详情栏是否展开。记住上次的选择 —— 习惯挂着看的人不用每次点开。
    @AppStorage("player.detailPanelExpanded") private var isDetailPanelExpanded: Bool = false
    /// 详情栏宽度，可以拖边框改，同样记住。
    @AppStorage("player.detailPanelWidth") private var detailPanelWidth: Double =
        PlayerView.defaultDetailPanelWidth
    /// 评论里点开的图。整窗铺开，压在播放器和详情栏之上。
    @State private var previewImageURL: URL?
    /// 一次拖拽开始时的宽度。DragGesture 给的是累计位移，得有个基准。
    @State private var detailPanelDragStartWidth: Double?
    @State private var isHoveringResizeHandle: Bool = false
    /// 顶部安全区高度（mac 的标题栏 / 手机的刘海）。播放层整层吃掉了安全区，
    /// 只有顶栏需要把它补回来，所以在这里记一份。
    @State private var safeAreaTopInset: CGFloat = 0
    /// 右侧安全区宽度（横屏时的刘海 / 挖孔那一侧）。右侧居中的旋转键要靠它避开。
    @State private var safeAreaTrailingInset: CGFloat = 0
    /// 手机上用户按过「旋转」。播放页默认竖屏，横屏只在这个值为 true 时成立。
    @State private var prefersLandscape: Bool = false
    /// 当前的摆法。跟着可用空间走，顶栏按钮也要按它决定行为。
    @State private var layoutMode: PlayerLayoutMode = .wide
    @State private var isDanmakuSettingsPresented: Bool = false
    @State private var scrubbingState = PlayerScrubbingState()
    @State private var scrubPreview = PlayerScrubPreviewController()
    @State private var autoHideTask: Task<Void, Never>?
    /// 播放音量。记着上次的选择 —— 每次进播放页都被拉回满音量没有道理。
    @AppStorage("player.volume") private var storedVolume: Double = 1
    @State private var temporaryBoostBaseRate: Float?
    @State private var temporaryBoostRate: Float?

    public init(
        request: PlaybackRequest,
        coordinator: PlaybackCoordinator,
        history: HistoryStore?,
        sourceCache: SourceSearchCache? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.request = request
        self.history = history
        self.sourceCache = sourceCache
        self.onClose = onClose
        self._coordinator = State(initialValue: coordinator)
        self._activeRequest = State(initialValue: request)
    }

    /// 播放层各块东西的露面规则。按钮和手势的处理都要问它，别各写各的。
    private var overlayVisibility: PlayerOverlayVisibility {
        PlayerOverlayVisibility(
            controlsVisible: controlsVisible,
            isTemporaryBoosting: temporaryBoostRate != nil,
            isBuffering: coordinator.backend.isBuffering,
            phase: coordinator.phase,
            duration: coordinator.backend.duration
        )
    }

    public var body: some View {
        GeometryReader { proxy in
            layout(mode: layoutMode, overlayVisibility: overlayVisibility)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: proxy.size, initial: true) { _, newSize in
                    layoutMode = PlayerLayoutPolicy.mode(
                        isCompact: horizontalSizeClass == .compact,
                        isLandscape: newSize.width > newSize.height
                    )
                }
                .background {
                    // GeometryReader 只有在自己吃掉安全区之后才报得出真实高度，
                    // 所以探针单独放一层 —— 布局本身仍按各自的摆法决定吃不吃。
                    GeometryReader { probe in
                        Color.clear
                            .onChange(of: probe.safeAreaInsets.top, initial: true) { _, inset in
                                safeAreaTopInset = inset
                            }
                            .onChange(of: probe.safeAreaInsets.trailing, initial: true) { _, inset in
                                safeAreaTrailingInset = inset
                            }
                    }
                    .ignoresSafeArea()
                }
        }
        .background(Color.black)
        // 评论里的图铺满整窗 —— 压在播放器和详情栏之上，mac 上不再是个小 sheet。
        .overlay {
            if let previewImageURL {
                CommentImagePreview(url: previewImageURL) {
                    self.previewImageURL = nil
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: previewImageURL)
        .animation(.easeInOut(duration: 0.28), value: overlayVisibility.isPreparing)
        .animation(.easeInOut(duration: 0.2), value: overlayVisibility.isRebuffering)
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isDetailPanelExpanded)
        .navigationTitle(isImmersive ? "" : activeRequest.episode.title)
        .toolbar(isImmersive ? .hidden : .automatic, for: .automatic)
        .toolbarBackground(.hidden, for: .automatic)
        .task {
            pictureInPictureController.setLifecycle(
                didStart: {
                    pictureInPicture.didStartPictureInPicture()
                },
                restoreUserInterface: { completion in
                    pictureInPicture.restoreUserInterface(completion: completion)
                }
            )
            prepareDetailModel(for: activeRequest)
            coordinator.backend.setVolume(Float(storedVolume))
            await danmakuController.prepare(for: activeRequest)
            chrome.setSidebarHidden(true)
            presentation.enterPlayback()
            if let history,
                let entry = try? history.entry(forDetailURL: activeRequest.anime.detailURL),
                entry.lastPositionMs > 0
            {
                coordinator.ingestResumeHint(entry, for: activeRequest)
                if coordinator.resumePromptPositionMs != nil {
                    showResumePrompt = true
                } else {
                    await coordinator.startPlayback(activeRequest, resume: false)
                    revealControlsTemporarily()
                }
            } else {
                await coordinator.startPlayback(activeRequest, resume: false)
                revealControlsTemporarily()
            }
        }
        .alert("继续观看？", isPresented: $showResumePrompt) {
            Button("从头开始") {
                Task {
                    await coordinator.startPlayback(activeRequest, resume: false)
                    revealControlsTemporarily()
                }
            }
            Button("继续观看") {
                Task {
                    await coordinator.startPlayback(activeRequest, resume: true)
                    revealControlsTemporarily()
                }
            }
        } message: {
            if let ms = coordinator.resumePromptPositionMs {
                Text("上次看到 \(formatMillis(ms))")
            }
        }
        .onChange(of: coordinator.phase) { _, newPhase in
            switch newPhase {
            case .playing:
                // 首帧未就绪时还在缓冲，reveal 只会记下可见意图，
                // 真正露出要等 isBuffering 落下后的 onChange。
                revealControlsTemporarily()
            case .paused, .failed, .finished:
                autoHideTask?.cancel()
                controlsVisible = true
            case .idle, .extracting, .loading:
                autoHideTask?.cancel()
                controlsVisible = false
            }
        }
        .onChange(of: coordinator.backend.isBuffering) { _, isBuffering in
            if isBuffering {
                // 提示自己会跟控制层错开摆，这里不再动控制层 —— 卡顿时把按钮收走，
                // 用户想拖出这一段反而找不到进度条。
                endTemporaryBoost()
                return
            }
            guard coordinator.phase == .playing else { return }
            revealControlsTemporarily()
        }
        .onChange(of: coordinator.backend.currentTime) { _, newTime in
            scrubbingState.syncPlaybackTime(newTime)
        }
        .onChange(of: activeRequest) { _, newRequest in
            prepareDetailModel(for: newRequest)
            Task {
                await danmakuController.prepare(for: newRequest)
            }
        }
        .onChange(of: enableDanmaku) { _, isEnabled in
            Task {
                await danmakuController.prepare(for: activeRequest, forceReload: isEnabled)
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
            // 朝向必须无条件恢复：进画中画时播放页一样会退场，界面留在横屏的话
            // 用户看到的就是一个横着的详情页。回到播放页时再由画中画恢复流程转回去。
            presentation.restoreDefaultPlaybackPresentation()
            guard !pictureInPictureController.isActive else { return }
            pictureInPictureController.setLifecycle()
            chrome.setSidebarHidden(false)
            Task { await coordinator.stop() }
        }
        .sheet(isPresented: $isDanmakuSettingsPresented) {
            PlayerDanmakuSettingsSheet()
        }
    }

    /// 手机竖屏：播放器只占上面 16:9 那块，控件必须瘦一圈，
    /// 次要按钮收进「更多」菜单，否则整块画面全被按钮盖住。
    private var isCompactChrome: Bool { layoutMode == .portraitStack }

    /// 手机竖屏专属摆件：中央三键换集、倍速进设置、右下只留全屏键。
    private var usesPhonePortraitChrome: Bool {
        PlayerPhoneChromePolicy.usesPhonePortraitChrome(
            mode: layoutMode,
            isPhone: presentation.supportsOrientationToggle
        )
    }

    /// 手机横屏专属摆件：顶栏那组按钮挪到左上角胶囊里。
    private var usesPhoneLandscapeChrome: Bool {
        PlayerPhoneChromePolicy.usesPhoneLandscapeChrome(
            mode: layoutMode,
            isPhone: presentation.supportsOrientationToggle
        )
    }

    /// 指上去或者正在拖，边线都亮着。
    private var isResizeHandleActive: Bool {
        isHoveringResizeHandle || detailPanelDragStartWidth != nil
    }

    static let defaultDetailPanelWidth: Double = 380
    static let minDetailPanelWidth: Double = 280
    static let maxDetailPanelWidth: Double = 620

    /// 手机竖屏底部那条控制胶囊：两侧留边、离底边留边、条高。
    /// 右上角那组按钮同高，所以只需要这一个高度。
    /// 底栏收起时往下滑多少。替代原来的 .move(edge: .bottom) 转场 ——
    /// 控制层现在常驻视图树（见 playerLayers 里的注释），用不了转场。
    static let controlsHideOffset: CGFloat = 28

    static let portraitBarSideMargin: CGFloat = 12
    static let portraitBarBottomMargin: CGFloat = 12
    static let portraitBarHeight: CGFloat = 44

    /// 手机竖屏时载入提示离画面底边的距离：越过整条控制胶囊，落在它上方。
    static let phonePortraitLoadingBottomInset: CGFloat =
        portraitBarBottomMargin + portraitBarHeight + 8

    /// 三种摆法：宽屏播放器 + 右侧详情栏、手机竖屏上下叠放、手机横屏整屏播放。
    @ViewBuilder
    private func layout(
        mode: PlayerLayoutMode,
        overlayVisibility: PlayerOverlayVisibility
    ) -> some View {
        switch mode {
        case .wide:
            HStack(spacing: 0) {
                playerLayers(overlayVisibility: overlayVisibility, fillsScreen: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isDetailPanelExpanded, let detailModel {
                    detailPanelResizeHandle
                    detailPanel(model: detailModel, onClose: { setDetailPanel(expanded: false) })
                        .frame(width: detailPanelWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            // 详情栏要顶到窗口上下边，不然右侧会空出一条和播放器对不齐的缝。
            .ignoresSafeArea()
        case .portraitStack:
            VStack(spacing: 0) {
                playerLayers(overlayVisibility: overlayVisibility, fillsScreen: false)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipped()
                if let detailModel {
                    detailPanel(model: detailModel, onClose: nil)
                        .frame(maxHeight: .infinity)
                }
            }
            // 顶部留给状态栏，底部那条 home indicator 归详情面板自己铺。
            .ignoresSafeArea(edges: .bottom)
        case .immersive:
            playerLayers(overlayVisibility: overlayVisibility, fillsScreen: true)
                .ignoresSafeArea()
        }
    }

    /// 详情栏左边那条可拖的边：整条边都能拖，平时是一根细线，指上去发亮。
    private var detailPanelResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            // 线画在贴着面板的那一侧：手柄自己再画一条的话，
            // 和玻璃面板的边就成了并排两根。
            .overlay(alignment: .trailing) {
                Rectangle()
                    // 静止时不画线：面板自己的边就是那一根，再加一条就成了两根。
                    // 指上去才亮起来，颜色跟随系统外观 —— 这条线在面板一侧，
                    // 不在画面上，不该跟着播放控件走深色。
                    .fill(Color.primary.opacity(isResizeHandleActive ? 0.6 : 0))
                    .frame(width: isResizeHandleActive ? 2 : 1)
                    .shadow(
                        color: .primary.opacity(isResizeHandleActive ? 0.35 : 0),
                        radius: 4
                    )
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHoveringResizeHandle = hovering
                }
            }
            .modifier(cursor.horizontalResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = detailPanelDragStartWidth ?? detailPanelWidth
                        detailPanelDragStartWidth = start
                        detailPanelWidth = min(
                            max(start - value.translation.width, Self.minDetailPanelWidth),
                            Self.maxDetailPanelWidth
                        )
                    }
                    .onEnded { _ in
                        detailPanelDragStartWidth = nil
                        withAnimation(.easeInOut(duration: 0.12)) {}
                    }
            )
            .accessibilityLabel("调整详情栏宽度")
    }

    @ViewBuilder
    private func detailPanel(model: PlayerDetailModel, onClose: (() -> Void)?) -> some View {
        PlayerDetailPanel(
            model: model,
            activeRequest: activeRequest,
            onClose: onClose
        ) { request in
            play(request: request)
        } onPreviewImage: { url in
            previewImageURL = url
        }
    }

    /// - Parameter fillsScreen: 播放器是否占满整屏。竖屏叠放时它只是上半部分，
    ///   不能再去吃安全区，否则会顶进状态栏、把下面的详情挤走。
    private func playerLayers(
        overlayVisibility: PlayerOverlayVisibility,
        fillsScreen: Bool
    ) -> some View {
        let screenEdges: Edge.Set = fillsScreen ? .all : []
        return ZStack(alignment: .bottom) {
            PlayerSurface(
                player: coordinator.backend.player,
                pictureInPictureController: pictureInPictureController,
                superResolutionMode: superResolutionMode,
                superResolutionDiagnostics: superResolutionDiagnostics
            )
            .ignoresSafeArea(edges: screenEdges)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControlsVisibility()
            }

            interaction.overlay(actions: interactionActions)
                .ignoresSafeArea(edges: screenEdges)

            if showsDanmaku {
                PlayerDanmakuOverlay(
                    controller: danmakuController,
                    currentTime: coordinator.backend.currentTime,
                    playbackRate: coordinator.backend.rate
                )
                .ignoresSafeArea(edges: screenEdges)
            }

            if overlayVisibility.showsPreparingScrim {
                Color.black.opacity(0.35)
                    .ignoresSafeArea(edges: screenEdges)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            noticeOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // 控制层收起时**不能用 if 摘掉**，只能靠透明度 + 关掉命中测试。
            //
            // 顶栏和底栏上挂着好几个 Menu，菜单的锚点就是那些按钮。把视图从树里
            // 摘掉，正开着的菜单会被连根拔起、当场消失 —— 而自动隐藏是 3 秒一到
            // 就触发的，用户菜单还没看完就被关掉了。留在树里菜单才活得下来。
            ZStack(alignment: .top) {
                // 顶部蒙层是给手机画面加的：亮画面下白图标会糊掉。
                // 桌面 / 平板的顶栏本来就压在标题栏一侧，再铺一层反而脏。
                if presentation.supportsOrientationToggle {
                    topControlsGradient
                }
                topBar
                    .padding(.horizontal, isCompactChrome ? 12 : 20)
                    // 铺满整屏的摆法把安全区吃掉了，顶栏得自己补回来，
                    // 否则在 mac 上压到交通灯、在刘海机上顶进挖孔；
                    // 竖屏叠放本来就在安全区里面，再补一次就白空一大截。
                    .padding(.top, topBarTopPadding(fillsScreen: fillsScreen))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(overlayVisibility.showsControls ? 1 : 0)
            .allowsHitTesting(overlayVisibility.showsControls)
            .accessibilityHidden(!overlayVisibility.showsControls)

            // 同上：底栏也留在树里。原来的 .move(edge: .bottom) 转场换成等效的
            // 位移，收起时往下滑一点再淡出，观感和原来一致。
            ZStack(alignment: .bottom) {
                bottomControlsGradient
                controls
                    .padding(
                        .horizontal,
                        usesPhonePortraitChrome
                            ? Self.portraitBarSideMargin
                            : (isCompactChrome ? 12 : 20)
                    )
                    .padding(
                        .bottom,
                        usesPhonePortraitChrome
                            ? Self.portraitBarBottomMargin
                            : (isCompactChrome ? 10 : 18)
                    )
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: overlayVisibility.showsControls ? 0 : Self.controlsHideOffset)
            .opacity(overlayVisibility.showsControls ? 1 : 0)
            .allowsHitTesting(overlayVisibility.showsControls)
            .accessibilityHidden(!overlayVisibility.showsControls)

            // 载入提示压在控制层之上：控制层出来也不许把它挤走，
            // 手机竖屏则落到底部那条控制胶囊的上方。
            if overlayVisibility.showsLoadingIndicator {
                loadingIndicator
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: usesPhonePortraitChrome ? .bottomLeading : .center
                    )
                    .padding(.leading, usesPhonePortraitChrome ? Self.portraitBarSideMargin : 0)
                    .padding(.bottom, usesPhonePortraitChrome ? Self.phonePortraitLoadingBottomInset : 0)
                    .transition(.opacity)
            }

            if overlayVisibility.showsTemporaryBoostBadge, let temporaryBoostRate {
                temporaryBoostBadge(temporaryBoostRate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

        }
        // 控件浮在画面上，而画面亮不亮谁也不知道 —— 外观跟着系统走，浅色下就成了
        // 白玻璃白字。整层钉死深色外观（AVPlayerViewController 也是这么干的），
        // 玻璃自己渲成深色，前景交给系统的 primary / secondary，不再手写白色。
        .environment(\.colorScheme, .dark)
    }

    /// 弹幕要等首帧真的上来才放。备片阶段画面还是黑的，这时候飘出第一批弹幕，
    /// 看起来就是「视频没开始，弹幕先跑了」。
    private var showsDanmaku: Bool {
        enableDanmaku && !overlayVisibility.isPreparing && coordinator.backend.currentTime > 0
    }

    /// 用户在设置里选的那个。菜单上的勾走这个，不受投屏影响。
    private var preferredSuperResolutionMode: SuperResolutionMode {
        SuperResolutionMode(rawValue: superResolutionRawMode)
            ?? PlaybackSettings.superResolutionModeDefault
    }

    /// 这一次真正喂给 `PlayerSurface` 的。投屏中会被压回 `.off`。
    private var superResolutionMode: SuperResolutionMode {
        SuperResolutionExternalPlaybackPolicy.effectiveMode(
            preferred: preferredSuperResolutionMode,
            isExternalPlaybackActive: coordinator.backend.isExternalPlaybackActive
        )
    }



    // MARK: - loading

    /// 载入提示上那句话。备片分「提取源」和「载入」两段，缓冲只有一句。
    private var loadingMessage: String {
        switch coordinator.phase {
        case .extracting: return "正在提取播放源"
        case .idle, .loading: return "正在载入视频"
        default: return "缓冲中"
        }
    }

    /// 备片 / 缓冲共用的那条提示。
    ///
    /// 做成一颗玻璃胶囊：转圈在左、字在右，不铺遮罩也不吃手势，摆在哪儿都不挡东西。
    /// 换集时文案会变，整条不重建，只让字自己交叉过渡。
    @ViewBuilder
    private var loadingIndicator: some View {
        HStack(spacing: 9) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.primary)

            Text(loadingMessage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize()
                .contentTransition(.opacity)
        }
        .padding(.leading, 12)
        .padding(.trailing, 15)
        .padding(.vertical, 9)
        .glassBackground(in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 12, y: 3)
        .animation(.easeInOut(duration: 0.2), value: loadingMessage)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(loadingMessage)
    }

    // MARK: - top bar

    /// 顶栏离窗顶多远。
    ///
    /// 铺满整屏的摆法把安全区吃掉了，顶栏得自己补回来，否则在刘海机上顶进挖孔；
    /// 竖屏叠放本来就在安全区里面，再补一次就白空一大截。
    ///
    /// 独立窗口那一路还要再让一截：安全区只让开了标题栏本身，关闭键正好贴着交通灯。
    private func topBarTopPadding(fillsScreen: Bool) -> CGFloat {
        let base: CGFloat = isCompactChrome ? 10 : 18
        let trafficLightClearance: CGFloat = presentation.prefersDedicatedWindow ? 18 : 0
        return base + trafficLightClearance + (fillsScreen ? safeAreaTopInset : 0)
    }

    /// 顶栏分两套：手机那套按触屏重排过（图标统一、按钮收纳），桌面 / 平板保持原样 ——
    /// 那些排布是给指针和大屏用的，跟着手机改反而难用。
    @ViewBuilder
    private var topBar: some View {
        if presentation.supportsOrientationToggle {
            phoneTopBar
        } else {
            desktopTopBar
        }
    }

    @ViewBuilder
    private var phoneTopBar: some View {
        let size: CGFloat = 40
        let font: Font = .system(size: 20, weight: .semibold)

        HStack(spacing: isCompactChrome ? 8 : 12) {
            switch closeButtonStyle {
            case .close:
                legacyCircularControlButton(
                    systemImage: "xmark",
                    size: isCompactChrome ? 34 : 42,
                    font: font
                ) {
                    close()
                }
            case .back:
                legacyCircularControlButton(
                    systemImage: "chevron.left",
                    size: 44,
                    font: .title3.weight(.bold)
                ) {
                    close()
                }
                .accessibilityLabel("返回")
            case .hidden:
                EmptyView()
            }

            // 手机横屏的左上角是空的（关闭键不摆），次要按钮就挪过来裹进胶囊，
            // 和左下角那组保持同一种质感；右上角只留设置。
            if usesPhoneLandscapeChrome {
                capsuleCluster {
                    secondaryTopButtons(size: size, font: font)
                }
            }

            downloadSpeedLabel

            Spacer(minLength: 8)

            HStack(spacing: isCompactChrome ? 6 : 10) {
                if usesPhoneLandscapeChrome {
                    volumeSlider
                }
                if !usesPhoneLandscapeChrome {
                    secondaryTopButtons(size: size, font: font)
                }
                settingsMenuButton(size: size, font: font)
            }
        }
    }

    @ViewBuilder
    private var desktopTopBar: some View {
        let size: CGFloat = isCompactChrome ? 34 : 40
        let font: Font = isCompactChrome ? .footnote : .subheadline

        HStack(spacing: isCompactChrome ? 8 : 12) {
            legacyCircularControlButton(
                systemImage: "xmark",
                size: isCompactChrome ? 34 : 42,
                font: font
            ) {
                close()
            }

            if pictureInPictureController.isSupported, !isCompactChrome {
                capsuleCluster {
                    iconControlButton(systemImage: "pip.enter", size: size, font: font) {
                        pictureInPictureController.start()
                        revealControlsTemporarily()
                    }
                }
            }

            downloadSpeedLabel

            Spacer(minLength: 8)

            // 窄分屏不摆：那种宽度连次要按钮都要收进「更多」。
            if !isCompactChrome {
                volumeSlider
            }

            capsuleCluster {
                if isCompactChrome {
                    // 窄分屏画面小，次要开关全收进「更多」。
                    moreMenuButton(size: size, font: font)
                } else {
                    superResolutionMenuButton(size: size, font: font)
                    systemPlayback.routePickerButton()
                    iconControlButton(systemImage: "text.bubble", size: size, font: font) {
                        presentDanmakuSettings()
                    }
                    iconControlButton(
                        systemImage: "rectangle.stack.badge.play",
                        size: size,
                        font: font
                    ) {
                        revealEpisodes()
                    }
                    .accessibilityLabel("选集")
                }
            }
        }
    }

    /// 超分菜单那一段的标题，后面缀上当前**实际**在跑什么。
    ///
    /// 放在标题里而不是菜单项里：iOS 的菜单是 UIKit 菜单，内容一被重建，
    /// 塞在里面的只读项会闪一下甚至整条消失；标题是菜单结构的一部分，稳得多。
    private var superResolutionSectionTitle: String {
        guard let summary = superResolutionDiagnostics.diagnostics.menuSummary else {
            return "超分辨率"
        }
        return "超分辨率 · \(summary)"
    }

    @ViewBuilder
    private func superResolutionMenuButton(size: CGFloat = 44, font: Font = .headline) -> some View {
        let device = SuperResolutionCapability.defaultDevice
        Menu {
            Section(superResolutionSectionTitle) {
                ForEach(SuperResolutionMode.allCases, id: \.self) { mode in
                    let supported = SuperResolutionCapability.isSupported(mode, on: device)
                    Button {
                        guard supported else { return }
                        superResolutionRawMode = mode.rawValue
                        revealControlsTemporarily()
                    } label: {
                        if preferredSuperResolutionMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .disabled(!supported)
                }
            }
        } label: {
            iconControlButtonLabel(
                systemImage: preferredSuperResolutionMode == .off
                    ? "wand.and.stars.inverse" : "wand.and.stars",
                size: size,
                font: font
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    /// 窄分屏下的次要操作：弹幕、画中画、超分。选集不在这里 —— 它就在下面的详情面板里。
    @ViewBuilder
    private func moreMenuButton(size: CGFloat, font: Font) -> some View {
        Menu {
            Button {
                presentDanmakuSettings()
            } label: {
                Label("弹幕设置", systemImage: "text.bubble")
            }

            if pictureInPictureController.isSupported {
                Button {
                    pictureInPictureController.start()
                    revealControlsTemporarily()
                } label: {
                    Label("画中画", systemImage: "pip.enter")
                }
            }

            Section(superResolutionSectionTitle) {
                ForEach(SuperResolutionMode.allCases, id: \.self) { mode in
                    let supported = SuperResolutionCapability.isSupported(
                        mode,
                        on: SuperResolutionCapability.defaultDevice
                    )
                    Button {
                        guard supported else { return }
                        superResolutionRawMode = mode.rawValue
                        revealControlsTemporarily()
                    } label: {
                        if preferredSuperResolutionMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .disabled(!supported)
                }
            }
        } label: {
            iconControlButtonLabel(systemImage: "ellipsis", size: size, font: font)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("更多")
    }

    /// 顶栏里除设置以外的次要按钮：画中画、投屏。
    @ViewBuilder
    private func secondaryTopButtons(size: CGFloat, font: Font) -> some View {
        if pictureInPictureController.isSupported {
            iconControlButton(systemImage: "pip.enter", size: size, font: font) {
                pictureInPictureController.start()
                revealControlsTemporarily()
            }
            .accessibilityLabel("画中画")
        }
        systemPlayback.routePickerButton()
            .frame(width: size, height: size)
    }

    /// 统一设置菜单：将弹幕设置、超分辨率等次要功能收纳在此。
    @ViewBuilder
    private func settingsMenuButton(size: CGFloat, font: Font) -> some View {
        let device = SuperResolutionCapability.defaultDevice
        Menu {
            Button {
                presentDanmakuSettings()
            } label: {
                Label("弹幕设置", systemImage: "text.bubble")
            }

            // 手机竖屏的右下角只放得下一个全屏键，倍速就收到这里来。
            if usesPhonePortraitChrome {
                Section("播放倍速") {
                    ForEach(Self.playbackRates, id: \.self) { rate in
                        Button {
                            coordinator.setRate(Float(rate))
                            revealControlsTemporarily()
                        } label: {
                            if isCurrentRate(rate) {
                                Label(rateMenuTitle(rate), systemImage: "checkmark")
                            } else {
                                Text(rateMenuTitle(rate))
                            }
                        }
                    }
                }
            }

            Section(superResolutionSectionTitle) {
                ForEach(SuperResolutionMode.allCases, id: \.self) { mode in
                    let supported = SuperResolutionCapability.isSupported(mode, on: device)
                    Button {
                        guard supported else { return }
                        superResolutionRawMode = mode.rawValue
                        revealControlsTemporarily()
                    } label: {
                        if preferredSuperResolutionMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .disabled(!supported)
                }
            }
        } label: {
            iconControlButtonLabel(systemImage: "gearshape.fill", size: size, font: font)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("设置")
    }

    private var closeButtonStyle: PlayerCloseButtonPolicy.Style {
        PlayerCloseButtonPolicy.style(mode: layoutMode, isPhone: presentation.supportsOrientationToggle)
    }

    /// 顶栏右上角那组按钮左边的音量胶囊。改的是这一路播放的音量，不动系统音量。
    @ViewBuilder
    private var volumeSlider: some View {
        PlayerVolumeSlider(
            volume: Binding(
                get: { Float(storedVolume) },
                set: { newValue in
                    storedVolume = Double(newValue)
                    coordinator.backend.setVolume(newValue)
                    revealControlsTemporarily()
                }
            )
        )
    }

    /// 下行速度。摆在顶栏左侧那组按钮后面 —— 它是诊断信息，右侧留给真正要点的东西。
    @ViewBuilder
    private var downloadSpeedLabel: some View {
        if let speedText = downloadSpeedText {
            Text(speedText)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
                .fixedSize()
                .accessibilityLabel("下行速度")
        }
    }

    /// 手机上横竖屏就是「全屏 / 退出全屏」，采用框形式的图标。
    private var orientationToggleIcon: String {
        prefersLandscape
            ? "arrow.down.right.and.arrow.up.left.square"
            : "arrow.up.left.and.arrow.down.right.square"
    }

    private var orientationToggleLabel: String {
        prefersLandscape ? "退出全屏" : "全屏"
    }

    /// 横屏下的缩小按钮。放在进度条右上角，挨着进度条。
    @ViewBuilder
    private var orientationToggleButton: some View {
        iconControlButton(
            systemImage: orientationToggleIcon,
            size: 44,
            font: .system(size: 24, weight: .semibold)
        ) {
            setLandscape(!prefersLandscape)
        }
        .accessibilityLabel(orientationToggleLabel)
    }

    /// 速度为 0 / 无采样时返回 nil —— 顶栏整个标签隐藏，不占位。
    private var downloadSpeedText: String? {
        guard let bps = coordinator.backend.downloadSpeedBps, bps > 0 else { return nil }
        return DownloadSpeedFormatter.format(bytesPerSecond: bps)
    }

    // MARK: - notices

    @ViewBuilder
    private var noticeOverlay: some View {
        VStack(spacing: 12) {
            if coordinator.requiresProxyWarning {
                GlassPanel {
                    Label(
                        "本地代理已关闭 —— 该规则需要 Referer，可能播放失败。在设置中可重新开启。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                }
            }
            if coordinator.externalPlaybackUnavailable {
                GlassPanel {
                    Label(
                        "投屏不可用 —— 该线路需要本地代理转发，而当前没有可用的局域网地址。",
                        systemImage: "airplayvideo"
                    )
                    .font(.footnote)
                }
            }
            if case .failed(let message) = coordinator.phase {
                GlassPanel {
                    Label(message, systemImage: "xmark.octagon")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
    }

    // MARK: - controls

    @ViewBuilder
    private var controls: some View {
        if usesPhonePortraitChrome {
            compactControls
        } else {
            regularControls
        }
    }

    /// 手机竖屏：底部一条玻璃胶囊，从左到右是播放键、已播、进度条、剩余、全屏键。
    ///
    /// 快进快退和换集都不在这儿：画面就那么大，塞满按钮不如把进度条做宽。换集在下面的
    /// 详情面板里，倍速在右上角的设置菜单里。
    @ViewBuilder
    private var compactControls: some View {
        HStack(spacing: 10) {
            iconControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                size: 36,
                font: .system(size: 19, weight: .semibold),
                isEnabled: overlayVisibility.playbackControlsEnabled
            ) {
                togglePlayPause()
            }
            .accessibilityLabel(coordinator.phase == .playing ? "暂停" : "播放")

            Text(
                PlayerTimeLabel.elapsed(
                    position: scrubbingState.position,
                    duration: coordinator.backend.duration
                )
            )
            .font(.subheadline.monospacedDigit().weight(.medium))
            .foregroundStyle(.primary)

            progressBar
                .dimmedWhenDisabled(overlayVisibility.playbackControlsEnabled)

            Text(
                PlayerTimeLabel.remaining(
                    position: scrubbingState.position,
                    duration: coordinator.backend.duration
                )
            )
            .font(.subheadline.monospacedDigit().weight(.medium))
            .foregroundStyle(.primary)

            iconControlButton(
                systemImage: orientationToggleIcon,
                size: 36,
                font: .system(size: 22, weight: .semibold)
            ) {
                setLandscape(!prefersLandscape)
            }
            .accessibilityLabel(orientationToggleLabel)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: Self.portraitBarHeight)
        .glassBackground(in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    /// 桌面 / 平板那套控制层，手机横屏也用它 —— 一行标题、一条进度条、下面左右两组按钮。
    @ViewBuilder
    private var regularControls: some View {
        let compact = isCompactChrome
        let isPhone = presentation.supportsOrientationToggle

        VStack(alignment: .leading, spacing: compact ? 6 : (isPhone ? 6 : 10)) {
            if !compact {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("\(activeRequest.anime.title) \(activeRequest.episode.title)")
                        // 这行是画面上唯一说明「在放什么」的字。原来的 subheadline 在
                        // 手机横屏上就偏小，摊到 Mac 整屏更是缩成一条。
                        .font((isPhone ? Font.title2 : .title).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // 标题自己占满剩下的宽度并在这里截断。少了这一层，长标题会按
                        // 理想宽度撑开整行，把右边的按钮顶出画面。
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)

                    if isPhone {
                        orientationToggleButton
                            .layoutPriority(1)
                    }
                }
            }

            HStack(spacing: compact ? 8 : 12) {
                Text(
                    PlayerTimeLabel.elapsed(
                        position: scrubbingState.position,
                        duration: coordinator.backend.duration
                    )
                )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .dimmedWhenDisabled(overlayVisibility.playbackControlsEnabled)

                progressBar

                Text(PlayerTimeLabel.total(coordinator.backend.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .dimmedWhenDisabled(overlayVisibility.playbackControlsEnabled)
            }

            HStack(spacing: 0) {
                playbackButtonRow(compact: compact)
                    .dimmedWhenDisabled(overlayVisibility.playbackControlsEnabled)
                Spacer(minLength: compact ? 8 : 24)
                capsuleCluster {
                    episodeCluster(
                        size: compact ? 34 : 40,
                        font: compact ? .footnote : .subheadline
                    )
                    speedMenuButton
                    if interaction.showsFullscreenToggle {
                        iconControlButton(
                            systemImage: isImmersive
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right",
                            size: compact ? 34 : 40,
                            font: compact ? .footnote : .subheadline
                        ) {
                            toggleImmersive()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    @ViewBuilder
    private var progressBar: some View {
        PlayerProgressBar(
            position: Binding(
                get: { scrubbingState.position },
                set: { newPosition in
                    scrubbingState.update(position: newPosition)
                    scrubPreview.request(at: newPosition)
                }
            ),
            duration: coordinator.backend.duration,
            bufferedTime: coordinator.backend.bufferedTime,
            onEditingChanged: handleScrubbingChanged,
            isIndeterminate: overlayVisibility.showsIndeterminateProgress
        ) {
            scrubPreviewCard
        }
    }

    /// 拖拽预览窗。抽帧在 HLS 上可能整段失败，那时只剩时间戳 —— 这是预期回落，不是错误。
    @ViewBuilder
    private var scrubPreviewCard: some View {
        VStack(spacing: 0) {
            if let image = scrubPreview.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 94)
                    .clipped()
            }
            Text(PlayerTimeLabel.format(scrubbingState.position))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
        }
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.primary.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    }

    /// 主播放操作：稿子里它们是裸图标，不收进胶囊。
    private func playbackButtonRow(compact: Bool) -> some View {
        let size: CGFloat = compact ? 36 : 44

        return HStack(spacing: compact ? 8 : 18) {
            iconControlButton(
                systemImage: "gobackward.10",
                size: size,
                font: compact ? .body : .title3
            ) {
                seekRelative(-10)
            }
            .accessibilityLabel("快退 10 秒")

            iconControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                size: size,
                font: compact ? .title3 : .title
            ) {
                togglePlayPause()
            }
            .accessibilityLabel(coordinator.phase == .playing ? "暂停" : "播放")

            iconControlButton(
                systemImage: "goforward.10",
                size: size,
                font: compact ? .body : .title3
            ) {
                seekRelative(10)
            }
            .accessibilityLabel("快进 10 秒")
        }
    }

    /// 一组次要操作收进单个 glass 胶囊。
    @ViewBuilder
    private func capsuleCluster<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassContainer {
            HStack(spacing: 2) {
                content()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .glassBackground(in: Capsule())
        }
    }

    @ViewBuilder
    private func temporaryBoostBadge(_ rate: Float) -> some View {
        Text(boostRateText(rate))
            .font(.headline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassBackground(in: Capsule())
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func episodeCluster(size: CGFloat = 44, font: Font = .headline) -> some View {
        iconControlButton(
            systemImage: "backward.end.fill",
            size: size,
            font: font,
            isEnabled: activeRequest.hasPreviousEpisode
        ) {
            playNeighborEpisode(step: -1)
        }

        iconControlButton(
            systemImage: "forward.end.fill",
            size: size,
            font: font,
            isEnabled: activeRequest.hasNextEpisode
        ) {
            playNeighborEpisode(step: 1)
        }
    }

    /// 顶栏的白图标会压在任意亮度的画面上 —— 蒙层要在图标那一段维持住浓度，
    /// 淡出留到图标下沿之后再开始，否则白底画面上的图标就糊了。
    private var topControlsGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .black.opacity(0.72), location: 0.45),
                .init(color: .black.opacity(0.32), location: 0.75),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: isCompactChrome ? 110 : 130)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var bottomControlsGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.38), location: 0.38),
                .init(color: .black.opacity(0.14), location: 0.72),
                .init(color: .clear, location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(maxWidth: .infinity)
        // 底部多了标题行，蒙层要比原来高一截才托得住；竖屏没有标题行，矮一半就够。
        .frame(height: isCompactChrome ? 116 : 200)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    private static let playbackRates: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0]

    private func rateMenuTitle(_ rate: Double) -> String {
        String(format: "%.2fx", rate)
    }

    private func isCurrentRate(_ rate: Double) -> Bool {
        let current = coordinator.backend.rate
        let effective = current > 0 ? Double(current) : 1
        return abs(effective - rate) < 0.001
    }

    @ViewBuilder
    private var speedMenuButton: some View {
        Menu {
            ForEach(Self.playbackRates, id: \.self) { rate in
                Button(rateMenuTitle(rate)) {
                    coordinator.setRate(Float(rate))
                    revealControlsTemporarily()
                }
            }
        } label: {
            Text(currentRateText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .frame(height: 40)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("播放倍速")
    }

    /// 长按倍速期间显示的是临时值，会在松手后弹回，所以直接读 backend 的实时 rate。
    private var currentRateText: String {
        let rate = coordinator.backend.rate
        let effective = rate > 0 ? rate : 1
        return String(format: "%gx", (effective * 100).rounded() / 100)
    }

    @ViewBuilder
    private func iconControlButton(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconControlButtonLabel(systemImage: systemImage, size: size, font: font)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconControlButtonLabel(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline
    ) -> some View {
        Image(systemName: systemImage)
            .font(font.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func legacyCircularControlButton(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            legacyCircularControlButtonLabel(systemImage: systemImage, size: size, font: font)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Circle())
    }

    @ViewBuilder
    private func legacyCircularControlButtonLabel(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline
    ) -> some View {
        ZStack {
            Image(systemName: systemImage)
                .font(font.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
        .glassBackground(in: Circle())
        .contentShape(Circle())
    }

    private var interactionActions: PlayerInteractionActions {
        PlayerInteractionActions(
            toggleControls: {
                toggleControlsVisibility()
            },
            togglePlayPause: {
                togglePlayPause()
            },
            seekRelative: { delta in
                seekRelative(delta)
            },
            beginTemporaryBoost: {
                beginTemporaryBoost()
            },
            updateTemporaryBoost: { rate in
                updateTemporaryBoost(rate: rate)
            },
            endTemporaryBoost: {
                endTemporaryBoost()
            }
        )
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        if editing {
            scrubbingState.begin(at: coordinator.backend.currentTime)
            scrubPreview.prepare(
                url: coordinator.currentMediaURL,
                headers: coordinator.currentMediaHeaders
            )
            autoHideTask?.cancel()
            controlsVisible = true
        } else {
            scrubPreview.reset()
            finishScrubbing()
        }
    }

    private func finishScrubbing() {
        guard let target = scrubbingState.finish() else { return }
        Task { await coordinator.seek(to: target) }
        revealControlsTemporarily()
    }

    private func seekRelative(_ delta: TimeInterval) {
        guard overlayVisibility.allowsPlaybackInteraction else { return }
        let target = min(max(coordinator.backend.currentTime + delta, 0), coordinator.backend.duration)
        Task { await coordinator.seek(to: target) }
        revealControlsTemporarily()
    }

    private func togglePlayPause() {
        guard overlayVisibility.allowsPlaybackInteraction else { return }
        if coordinator.phase == .playing {
            coordinator.pause()
        } else {
            coordinator.resume()
        }
        revealControlsTemporarily()
    }

    private func beginTemporaryBoost() {
        guard overlayVisibility.allowsPlaybackInteraction,
              temporaryBoostBaseRate == nil,
              PlayerTemporaryBoostRate.canBegin(
                  isPlaying: coordinator.phase == .playing,
                  isBuffering: coordinator.backend.isBuffering
              )
        else { return }
        temporaryBoostBaseRate = max(coordinator.backend.rate, 1.0)
        let rate = PlayerTemporaryBoostRate.defaultRate
        temporaryBoostRate = rate
        coordinator.setRate(rate)
        revealControlsTemporarily()
    }

    private func updateTemporaryBoost(rate: Float) {
        guard temporaryBoostBaseRate != nil else { return }
        temporaryBoostRate = rate
        coordinator.setRate(rate)
        revealControlsTemporarily()
    }

    private func endTemporaryBoost() {
        guard let baseRate = temporaryBoostBaseRate else { return }
        temporaryBoostBaseRate = nil
        temporaryBoostRate = nil
        coordinator.setRate(baseRate)
        revealControlsTemporarily()
    }

    private func playNeighborEpisode(step: Int) {
        let nextRequest: PlaybackRequest?
        switch step {
        case -1:
            nextRequest = activeRequest.previousEpisodeRequest
        case 1:
            nextRequest = activeRequest.nextEpisodeRequest
        default:
            nextRequest = nil
        }
        guard let nextRequest else { return }

        play(request: nextRequest)
    }

    private func revealControlsTemporarily() {
        controlsVisible = true
        autoHideTask?.cancel()
        guard coordinator.phase == .playing,
              !coordinator.backend.isBuffering,
              !scrubbingState.isActive
        else { return }
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if coordinator.phase == .playing && !scrubbingState.isActive {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = false
                    }
                }
            }
        }
    }

    private func toggleControlsVisibility() {
        autoHideTask?.cancel()
        if controlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                controlsVisible = false
            }
        } else {
            revealControlsTemporarily()
        }
    }

    private func toggleImmersive() {
        let next = !isImmersive
        withAnimation(.easeInOut(duration: 0.25)) {
            isImmersive = next
        }
        chrome.setSidebarHidden(next)
        presentation.setSystemFullscreen(next)
        revealControlsTemporarily()
    }

    private func close() {
        // 先落盘当前帧，再关页；避免只依赖 onDisappear 时进度还没写完 UI 已刷新。
        Task { @MainActor in
            await coordinator.stop()
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        }
    }

    private func prepareDetailModel(for request: PlaybackRequest) {
        let enabledRules = ruleStore.enabledRules()
        if let detailModel {
            detailModel.syncCurrentRequest(request, rules: enabledRules)
        } else {
            detailModel = PlayerDetailModel(
                currentRequest: request,
                rules: enabledRules,
                cachedSources: sourceCache
            )
        }
    }

    /// 顶栏「选集」：把用户送到能选集的地方。
    ///
    /// 宽屏是展开右侧详情栏；手机竖屏详情就在下面，只要把 tab 拨过去；
    /// 手机横屏则先转回竖屏 —— 横屏没有地方摆这个面板。
    private func revealEpisodes() {
        prepareDetailModel(for: activeRequest)
        detailModel?.tab = .episodes
        switch layoutMode {
        case .wide:
            setDetailPanel(expanded: !isDetailPanelExpanded)
        case .portraitStack:
            revealControlsTemporarily()
        case .immersive:
            setLandscape(false)
        }
    }

    private func setDetailPanel(expanded: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isDetailPanelExpanded = expanded
        }
        revealControlsTemporarily()
    }

    /// 手机上的「旋转」。朝向只跟这个开关走，不跟随重力。
    private func setLandscape(_ landscape: Bool) {
        prefersLandscape = landscape
        presentation.setPlaybackLandscape(landscape)
        revealControlsTemporarily()
    }

    private func presentDanmakuSettings() {
        autoHideTask?.cancel()
        controlsVisible = true
        isDanmakuSettingsPresented = true
    }

    private func play(request: PlaybackRequest) {
        showResumePrompt = false
        activeRequest = request
        Task {
            await coordinator.startPlayback(request, resume: false)
            revealControlsTemporarily()
        }
    }

    private func formatMillis(_ ms: Int) -> String {
        PlayerTimeLabel.format(TimeInterval(ms) / 1000.0)
    }

    private func boostRateText(_ rate: Float) -> String {
        String(format: "%.1fX", rate)
    }
}

// MARK: - chrome controller environment

/// 让 `PlayerView` 能请求外层根视图隐藏 / 恢复 sidebar 等 chrome 元素。
/// 走 Environment 注入而不是直接改全局状态，让 CompactRootView（没有 sidebar）
/// 可以用空实现接入。
public struct PlayerChromeController: Sendable {
    private let setSidebarHiddenImpl: @MainActor @Sendable (Bool) -> Void

    public init(
        setSidebarHidden: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.setSidebarHiddenImpl = setSidebarHidden
    }

    @MainActor
    public func setSidebarHidden(_ hidden: Bool) {
        setSidebarHiddenImpl(hidden)
    }
}

public struct PlayerPresentationController: Sendable {
    private let enterPlaybackImpl: @MainActor @Sendable () -> Void
    private let setLandscapeImpl: @MainActor @Sendable (Bool) -> Void
    private let restoreDefaultImpl: @MainActor @Sendable () -> Void
    private let setSystemFullscreenImpl: @MainActor @Sendable (Bool) -> Void

    /// macOS 专用：为 true 时播放请求会打开独立窗口，而不是在主窗口导航栈内替换。
    /// 仅由 macOS App 入口注入，iOS / iPad 保持 false 以维持原行为。
    public let prefersDedicatedWindow: Bool

    /// 宿主是否支持手动翻屏。只有手机会给 true —— 别的平台没有「旋转」这回事，
    /// 播放页也就不该显示那个按钮。
    public let supportsOrientationToggle: Bool

    public init(
        enterPlayback: @escaping @MainActor @Sendable () -> Void = {},
        setPlaybackLandscape: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        restoreDefaultPlaybackPresentation: @escaping @MainActor @Sendable () -> Void = {},
        setSystemFullscreen: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        prefersDedicatedWindow: Bool = false,
        supportsOrientationToggle: Bool = false
    ) {
        self.enterPlaybackImpl = enterPlayback
        self.setLandscapeImpl = setPlaybackLandscape
        self.restoreDefaultImpl = restoreDefaultPlaybackPresentation
        self.setSystemFullscreenImpl = setSystemFullscreen
        self.prefersDedicatedWindow = prefersDedicatedWindow
        self.supportsOrientationToggle = supportsOrientationToggle
    }

    /// 播放页开始占屏。手机上这一步只是声明「现在在播放页」，朝向仍是竖屏。
    @MainActor
    public func enterPlayback() {
        enterPlaybackImpl()
    }

    /// 手动翻屏。true 锁横屏，false 回竖屏。
    @MainActor
    public func setPlaybackLandscape(_ landscape: Bool) {
        setLandscapeImpl(landscape)
    }

    @MainActor
    public func restoreDefaultPlaybackPresentation() {
        restoreDefaultImpl()
    }

    @MainActor
    public func setSystemFullscreen(_ fullscreen: Bool) {
        setSystemFullscreenImpl(fullscreen)
    }
}

public struct PlayerSystemPlaybackController: @unchecked Sendable {
    private let makeRoutePickerButtonImpl: @MainActor () -> AnyView

    public init(
        makeRoutePickerButton: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.makeRoutePickerButtonImpl = makeRoutePickerButton
    }

    @MainActor
    public func routePickerButton() -> AnyView {
        makeRoutePickerButtonImpl()
    }
}

public struct PlayerPictureInPictureLifecycleController: Sendable {
    private let didStartImpl: @MainActor @Sendable () -> Void
    private let restoreImpl: @MainActor @Sendable (@escaping (Bool) -> Void) -> Void

    public init(
        didStartPictureInPicture: @escaping @MainActor @Sendable () -> Void = {},
        restoreUserInterface: @escaping @MainActor @Sendable (@escaping (Bool) -> Void) -> Void = { completion in
            completion(true)
        }
    ) {
        self.didStartImpl = didStartPictureInPicture
        self.restoreImpl = restoreUserInterface
    }

    @MainActor
    public func didStartPictureInPicture() {
        didStartImpl()
    }

    @MainActor
    public func restoreUserInterface(completion: @escaping (Bool) -> Void) {
        restoreImpl(completion)
    }
}

public struct PlayerInteractionActions: Sendable {
    public let toggleControls: @MainActor @Sendable () -> Void
    public let togglePlayPause: @MainActor @Sendable () -> Void
    public let seekRelative: @MainActor @Sendable (TimeInterval) -> Void
    public let beginTemporaryBoost: @MainActor @Sendable () -> Void
    public let updateTemporaryBoost: @MainActor @Sendable (Float) -> Void
    public let endTemporaryBoost: @MainActor @Sendable () -> Void

    public init(
        toggleControls: @escaping @MainActor @Sendable () -> Void = {},
        togglePlayPause: @escaping @MainActor @Sendable () -> Void = {},
        seekRelative: @escaping @MainActor @Sendable (TimeInterval) -> Void = { _ in },
        beginTemporaryBoost: @escaping @MainActor @Sendable () -> Void = {},
        updateTemporaryBoost: @escaping @MainActor @Sendable (Float) -> Void = { _ in },
        endTemporaryBoost: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.toggleControls = toggleControls
        self.togglePlayPause = togglePlayPause
        self.seekRelative = seekRelative
        self.beginTemporaryBoost = beginTemporaryBoost
        self.updateTemporaryBoost = updateTemporaryBoost
        self.endTemporaryBoost = endTemporaryBoost
    }
}

/// 鼠标指针形状由宿主提供 —— 改指针是 AppKit 的事，TubeKit 里不碰。
/// 默认什么都不做，只有 macOS App 入口会注入真正的「左右拉伸」指针。
public struct PlayerCursorController: Sendable {
    /// 套在可拖边框上的修饰器。
    public let horizontalResize: PlayerCursorModifier

    public init(horizontalResize: PlayerCursorModifier = PlayerCursorModifier()) {
        self.horizontalResize = horizontalResize
    }
}

/// 一个可注入的 `ViewModifier`：宿主给什么就套什么，不给就原样透传。
public struct PlayerCursorModifier: ViewModifier, @unchecked Sendable {
    private let transform: (@MainActor (AnyView) -> AnyView)?

    public nonisolated init() {
        self.transform = nil
    }

    public nonisolated init(_ transform: @escaping @MainActor (AnyView) -> AnyView) {
        self.transform = transform
    }

    public func body(content: Content) -> some View {
        if let transform {
            transform(AnyView(content))
        } else {
            AnyView(content)
        }
    }
}

public struct PlayerInteractionController: @unchecked Sendable {
    public let showsFullscreenToggle: Bool
    private let makeOverlayImpl: @MainActor (PlayerInteractionActions) -> AnyView

    public init(
        showsFullscreenToggle: Bool = true,
        makeOverlay: @escaping @MainActor (PlayerInteractionActions) -> AnyView = { _ in
            AnyView(EmptyView())
        }
    ) {
        self.showsFullscreenToggle = showsFullscreenToggle
        self.makeOverlayImpl = makeOverlay
    }

    @MainActor
    public func overlay(actions: PlayerInteractionActions) -> AnyView {
        makeOverlayImpl(actions)
    }
}

private struct PlayerChromeControllerKey: EnvironmentKey {
    static let defaultValue = PlayerChromeController()
}

private struct PlayerPresentationControllerKey: EnvironmentKey {
    static let defaultValue = PlayerPresentationController()
}

private struct PlayerSystemPlaybackControllerKey: EnvironmentKey {
    static let defaultValue = PlayerSystemPlaybackController()
}

private struct PlayerPictureInPictureLifecycleControllerKey: EnvironmentKey {
    static let defaultValue = PlayerPictureInPictureLifecycleController()
}

private struct PlayerInteractionControllerKey: EnvironmentKey {
    static let defaultValue = PlayerInteractionController()
}

private struct PlayerCursorControllerKey: EnvironmentKey {
    static let defaultValue = PlayerCursorController()
}

extension EnvironmentValues {
    public var playerChromeController: PlayerChromeController {
        get { self[PlayerChromeControllerKey.self] }
        set { self[PlayerChromeControllerKey.self] = newValue }
    }

    public var playerPresentationController: PlayerPresentationController {
        get { self[PlayerPresentationControllerKey.self] }
        set { self[PlayerPresentationControllerKey.self] = newValue }
    }

    public var playerSystemPlaybackController: PlayerSystemPlaybackController {
        get { self[PlayerSystemPlaybackControllerKey.self] }
        set { self[PlayerSystemPlaybackControllerKey.self] = newValue }
    }

    public var playerPictureInPictureController: PlayerPictureInPictureLifecycleController {
        get { self[PlayerPictureInPictureLifecycleControllerKey.self] }
        set { self[PlayerPictureInPictureLifecycleControllerKey.self] = newValue }
    }

    public var playerInteractionController: PlayerInteractionController {
        get { self[PlayerInteractionControllerKey.self] }
        set { self[PlayerInteractionControllerKey.self] = newValue }
    }

    public var playerCursorController: PlayerCursorController {
        get { self[PlayerCursorControllerKey.self] }
        set { self[PlayerCursorControllerKey.self] = newValue }
    }
}

private extension View {
    /// 备片阶段的灰显：按不动，也看得出按不动。整组一起压，比逐个按钮传 `isEnabled` 干净。
    @ViewBuilder
    func dimmedWhenDisabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
