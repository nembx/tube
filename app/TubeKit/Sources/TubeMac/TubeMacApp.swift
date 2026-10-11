import TubeKit
import AppKit
import SwiftUI

/// SwiftPM 可执行入口 —— 让你不用建 Xcode workspace 就能直接 `swift run TubeMac`
/// 把整个 macOS App 跑起来。
///
/// 这个 target 与 `app/Tube-macOS/Sources/TubeApp.swift`（Xcode App target 用的入口）
/// 内容完全一致，只是为了让 SwiftPM 找得到它必须放在包根之内。
///
/// 当你按 仓库 `README.md` 的步骤建好真正的 Xcode App target 之后，这个文件可以
/// 被忽略 —— Xcode App target 会用 `Tube-macOS/Sources/TubeApp.swift`。
@main
struct TubeMacApp: App {
    /// macOS App 持有唯一 session，所有窗口（主窗口 + 独立播放器窗口）共享同一份 store / history。
    /// 启动时为 nil，加载完成后再注入，避免 TubeRoot 长时间卡在 empty fallback 导致无规则/无播源。
    @State private var session: TubeSession?

    var body: some Scene {
        // 主窗口：正常使用 TubeRoot，传入共享 session
        WindowGroup {
            // OAuth 回调 `nembx-tube://…` 到达时，SwiftUI 默认会为外部事件新开一个窗口。
            // 声明现有主窗口「优先处理」这类事件，URL 就交给当前窗口里的 onOpenURL，不再多开。
            Group {
                if let session {
                    TubeRoot(session: session)
                        .environment(\.playerPresentationController, makePresentationController())
                        .environment(\.playerInteractionController, makeInteractionController())
                } else {
                    ProgressView("正在启动…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task {
                            session = await TubeSession.makePersistent()
                        }
                }
            }
            .handlesExternalEvents(preferring: ["nembx-tube"], allowing: ["nembx-tube"])
        }
        .handlesExternalEvents(matching: ["nembx-tube"])
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        // 宽屏走沉浸式外壳：内容直接铺到窗口最上沿，标题栏只剩交通灯浮在画面上。
        .windowStyle(.hiddenTitleBar)

        // 独立播放器窗口：macOS 专用，关闭此窗口不影响主 App 窗口
        WindowGroup(id: "player", for: PlaybackRequest.self) { $request in
            if let request, let session {
                PlayerView(
                    request: request,
                    coordinator: PlaybackCoordinator(
                        history: session.history,
                        progressTracker: session.collections
                    ),
                    history: session.history
                )
                .environment(session.store)
                .environment(session.history)
                .environment(\.playerPresentationController, makePresentationController())
                .environment(\.playerInteractionController, makeInteractionController())
            }
        }
        // 独立播放器窗口不接外部 URL 事件，免得回调把它当成落点新开一个。
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
    }

    private func makePresentationController() -> PlayerPresentationController {
        PlayerPresentationController(
            restoreDefaultPlaybackPresentation: {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            },
            setSystemFullscreen: { fullscreen in
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                if window.styleMask.contains(.fullScreen) != fullscreen {
                    window.toggleFullScreen(nil)
                }
            },
            prefersDedicatedWindow: true
        )
    }

    private func makeInteractionController() -> PlayerInteractionController {
        PlayerInteractionController(
            makeOverlay: { actions in
                AnyView(PlayerKeyboardInteractionOverlay(actions: actions))
            }
        )
    }
}
