// xcode: set sdk=iOS

import TubeKit
import Observation
import UIKit

/// 手机上播放页的朝向切换与系统装饰状态。
///
/// 关键在于「请求旋转」和「改掉声明支持的朝向」必须**成对**发生：只发
/// `requestGeometryUpdate` 的话，App 依旧声明支持横屏，退出播放页之后用户手一动，
/// 系统就名正言顺地把界面转回横屏 —— 详情页残留横屏正是这么来的。
/// 规则本身在 `PlayerOrientationPolicy`，这里只负责翻译成 UIKit 的说法并下发。
///
/// 播放页默认竖屏（上播放器下详情），横屏只在用户按了「旋转」之后成立，
/// 所以每次翻屏都要连朝向掩码一起改，而不是只请求一次几何变更。
@MainActor
@Observable
final class PlayerOrientationLock {
    static let shared = PlayerOrientationLock()

    /// 播放页是否正占着整屏。
    private(set) var isPlaybackPresented = false
    /// 用户在播放页里按过「旋转」。
    private(set) var prefersLandscape = false

    /// 只有横屏播放才藏起状态栏和 Home Indicator：竖屏播放页下半屏还是正常界面，
    /// 把系统装饰收掉反而怪。
    var isImmersivePlayback: Bool { isPlaybackPresented && prefersLandscape }

    private init() {}

    /// 供 `UIApplicationDelegate` 回答系统的朝向询问。
    var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch PlayerOrientationPolicy.allowed(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone,
            isPlaybackPresented: isPlaybackPresented,
            prefersLandscape: prefersLandscape
        ) {
        case .portraitOnly: .portrait
        case .landscapeOnly: .landscape
        case .any: .all
        }
    }

    /// 进播放页。默认竖屏 —— 翻不翻屏由用户按键决定。
    func enterPlayback() {
        apply(playbackPresented: true, prefersLandscape: false)
    }

    /// 播放页里的「旋转」。给两个横屏方向，系统会挑离用户当前握持姿势最近的那个 ——
    /// 写死一个方向的话，反着拿手机的人会被硬掰过来。
    func setLandscape(_ landscape: Bool) {
        apply(playbackPresented: true, prefersLandscape: landscape)
    }

    func exitPlayback() {
        apply(playbackPresented: false, prefersLandscape: false)
    }

    private func apply(playbackPresented: Bool, prefersLandscape: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard isPlaybackPresented != playbackPresented || self.prefersLandscape != prefersLandscape
        else { return }
        isPlaybackPresented = playbackPresented
        self.prefersLandscape = prefersLandscape
        let orientations: UIInterfaceOrientationMask = prefersLandscape ? .landscape : .portrait

        guard let scene = Self.activeWindowScene() else { return }
        // 顺序要紧：先让系统重新问一遍允许哪些朝向，再请求几何变更。
        // 反过来的话请求的朝向还不在允许集合里，会被直接驳回。
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
    }

    static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
