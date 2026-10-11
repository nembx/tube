import Foundation

/// 手机上「什么时候允许横屏」的唯一规则。
///
/// 这条规则出过事，所以单独拎出来：从前进播放页只发了一次旋转请求，却没有改掉
/// App 声明支持的朝向。结果退出播放页之后系统仍然认为横屏是合法的，用户手一动
/// 就把界面转回横屏 —— 详情页残留横屏就是这么来的。
///
/// 宿主平台要做的只是把 `allowed` 的结果如实翻译成系统的朝向掩码，并在每次切换时
/// 让系统重新问一遍。只要不允许，系统就没有转回去的余地。
public enum PlayerOrientationPolicy {

    /// 当前允许的朝向集合。
    public enum Allowed: Sendable, Equatable {
        /// 只允许竖屏 —— 手机上的常态。
        case portraitOnly
        /// 只允许横屏 —— 手机上的播放页。
        case landscapeOnly
        /// 不限制 —— iPad / Mac。
        case any
    }

    /// - Parameters:
    ///   - isPhone: 是否是只有竖屏常态的手机。iPad 传 `false`。
    ///   - isPlaybackPresented: 播放页是否正占据整屏。画中画期间播放页已经退场，
    ///     应当传 `false`，否则 App 会一直卡在横屏。
    ///   - prefersLandscape: 用户在播放页里按了「旋转」。播放页默认竖屏，只有
    ///     按过这个键才允许横屏 —— 不跟随重力，方向什么时候变由用户说了算。
    public static func allowed(
        isPhone: Bool,
        isPlaybackPresented: Bool,
        prefersLandscape: Bool = false
    ) -> Allowed {
        guard isPhone else { return .any }
        guard isPlaybackPresented else { return .portraitOnly }
        return prefersLandscape ? .landscapeOnly : .portraitOnly
    }
}
