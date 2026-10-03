import CezzuKit
import AVKit
import SwiftUI
import UIKit
import AVFoundation

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { PlayerOrientationLock.shared.supportedInterfaceOrientations }
    }
}

@main
struct TubeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// 播放页占屏期间的朝向与系统装饰状态。竖屏播放保留状态栏，横屏才全收起来。
    private var orientation: PlayerOrientationLock { .shared }

    var body: some Scene {
        WindowGroup {
            CezzuRoot()
                // 全屏播放时藏起系统装饰。想看时间信号从屏幕顶边下滑，
                // 系统会自己把状态栏临时唤出来 —— 这是 iOS 对隐藏状态栏的既定行为。
                .statusBarHidden(orientation.isImmersivePlayback)
                .persistentSystemOverlays(orientation.isImmersivePlayback ? .hidden : .automatic)
                .task {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
                .environment(
                    \.playerPresentationController,
                    PlayerPresentationController(
                        enterPlayback: {
                            PlayerOrientationLock.shared.enterPlayback()
                        },
                        setPlaybackLandscape: { landscape in
                            PlayerOrientationLock.shared.setLandscape(landscape)
                        },
                        restoreDefaultPlaybackPresentation: {
                            PlayerOrientationLock.shared.exitPlayback()
                        },
                        supportsOrientationToggle: UIDevice.current.userInterfaceIdiom == .phone
                    )
                )
                .environment(\.playerSystemPlaybackController, PlayerSystemPlaybackController(
                    makeRoutePickerButton: {
                        AnyView(
                            PlayerRoutePickerButton()
                                .frame(width: 44, height: 44)
                        )
                    }
                ))
                .environment(\.playerPictureInPictureController, PlayerPictureInPictureLifecycleController(
                    restoreUserInterface: { completion in
                        // 从画中画回到播放页，等于重新进一次全屏播放。
                        PlayerOrientationLock.shared.enterPlayback()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            completion(true)
                        }
                    }
                ))
                .environment(\.playerInteractionController, PlayerInteractionController(
                    showsFullscreenToggle: false,
                    makeOverlay: { actions in
                        AnyView(PlayerInteractionOverlay(actions: actions))
                    }
                ))
                // 黑白 monochrome：浅色黑 / 深色白，跟随 AccentColor 与系统 color scheme。
                .tint(Color.accentColor)
        }
    }
}
