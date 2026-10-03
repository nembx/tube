import CezzuKit
import AppKit
import SwiftUI

/// SwiftPM 可执行入口 —— 让你不用建 Xcode workspace 就能直接 `swift run CezzuMac`
/// 把整个 macOS App 跑起来。
///
/// 这个 target 与 `cezzu/Cezzu-macOS/Sources/CezzuApp.swift`（Xcode App target 用的入口）
/// 内容完全一致，只是为了让 SwiftPM 找得到它必须放在包根之内。
///
/// 当你按 `cezzu/README.md` 的步骤建好真正的 Xcode App target 之后，这个文件可以
/// 被忽略 —— Xcode App target 会用 `Cezzu-macOS/Sources/CezzuApp.swift`。
@main
struct CezzuMacApp: App {
    /// macOS App 持有唯一 session，所有窗口（主窗口 + 独立播放器窗口）共享同一份 store / history。
    /// 启动时为 nil，加载完成后再注入，避免 CezzuRoot 长时间卡在 empty fallback 导致无规则/无播源。
    @State private var session: CezzuSession?

    var body: some Scene {
        // 主窗口：正常使用 CezzuRoot，传入共享 session
        WindowGroup {
            Group {
                if let session {
                    CezzuRoot(session: session)
                        .environment(\.playerPresentationController, makePresentationController())
                        .environment(\.playerInteractionController, makeInteractionController())
                } else {
                    ProgressView("正在启动…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task {
                            session = await CezzuSession.makePersistent()
                        }
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        // 宽屏走沉浸式外壳：内容直接铺到窗口最上沿，标题栏只剩交通灯浮在画面上。
        .windowStyle(.hiddenTitleBar)

        // 独立播放器窗口：macOS 专用，关闭此窗口不影响主 App 窗口
        WindowGroup(id: "player", for: PlaybackRequest.self) { $request in
            if let request, let session {
                PlayerView(
                    request: request,
                    coordinator: PlaybackCoordinator(history: session.history),
                    history: session.history
                )
                .environment(session.store)
                .environment(session.history)
                .environment(\.playerPresentationController, makePresentationController())
                .environment(\.playerInteractionController, makeInteractionController())
            }
        }
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
