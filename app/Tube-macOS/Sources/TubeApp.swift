import CezzuKit
import AppKit
import SwiftUI

@main
struct TubeApp: App {
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
                        .environment(\.playerCursorController, makeCursorController())
                        // .hiddenTitleBar 让窗口顶部那条安全区只剩交通灯和返回按钮，
                        // 顶栏要升进去跟它们同行，否则会低一行压到页面内容上。
                        .environment(\.regularTopBarPlacement, .inTitleBar)
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
                .environment(\.playerCursorController, makeCursorController())
            }
        }
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
    }

    /// 可拖边框上的指针形状。macOS 15 起有 SwiftUI 的 `pointerStyle`，
    /// 更早的系统退回 AppKit 的 `NSCursor`。
    private func makeCursorController() -> PlayerCursorController {
        PlayerCursorController(
            horizontalResize: PlayerCursorModifier { view in
                if #available(macOS 15.0, *) {
                    return AnyView(view.pointerStyle(.columnResize))
                }
                return AnyView(
                    view.onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                )
            }
        )
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
