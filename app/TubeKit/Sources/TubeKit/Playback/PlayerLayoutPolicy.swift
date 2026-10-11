import Foundation

/// 播放页的三种摆法。
public enum PlayerLayoutMode: Sendable, Equatable {
    /// 宽屏（mac / iPad）：播放器占左边，详情面板是右侧可收起的一栏。
    case wide
    /// 手机竖屏：上面播放器，下面详情，像 YouTube / B 站那样。
    case portraitStack
    /// 手机横屏：整屏播放，详情让位给画面。
    case immersive
}

/// 播放页该用哪种摆法的唯一规则。
///
/// 只看「横向空间够不够宽」和「当前是不是横屏」，不看平台 —— iPad 分屏变窄时
/// 走的就是手机那套，Mac 窗口再窄也仍然是宽屏摆法（有独立窗口托着）。
public enum PlayerLayoutPolicy {
    /// - Parameters:
    ///   - isCompact: 横向尺寸类是否紧凑（iPhone 全部姿态、iPad 窄分屏）。
    ///   - isLandscape: 当前可用空间是不是横的。
    public static func mode(isCompact: Bool, isLandscape: Bool) -> PlayerLayoutMode {
        guard isCompact else { return .wide }
        return isLandscape ? .immersive : .portraitStack
    }
}
