import Foundation

/// 播放页左上角那个键该长什么样的唯一规则。
///
/// 播放页在手机上是叠在 tab 之上的浮层，关掉它就回到进来时的详情页 —— 所以竖屏下
/// 它是「返回」而不是「关闭」。横屏则干脆不摆：那个角落被状态栏和挖孔挤着，而用户
/// 手边已经有旋转键，先回竖屏再返回是同一条路。
public enum PlayerCloseButtonPolicy {

    public enum Style: Sendable, Equatable {
        /// 叉。iPad / Mac 的播放页是独立一屏 / 一窗，关掉就是关掉。
        case close
        /// 返回箭头。手机竖屏，退回详情页。
        case back
        /// 不摆。手机横屏，先按旋转键回竖屏。
        case hidden
    }

    /// - Parameters:
    ///   - mode: 当前的摆法。
    ///   - isPhone: 是否是手机（有横竖屏旋转键的那种）。iPad / Mac 传 `false`。
    public static func style(mode: PlayerLayoutMode, isPhone: Bool) -> Style {
        guard isPhone else { return .close }
        return mode == .immersive ? .hidden : .back
    }
}
