import Foundation

/// 手机播放页专属摆件的唯一规则。
///
/// 手机的画面比 iPad / Mac 小得多，控制层因此走了另一套摆法：竖屏把「上一集 / 下一集」
/// 顶到画面正中（十秒快进快退在这么小的画面上不如换集常用），倍速收进右上角的设置菜单；
/// 横屏则把顶栏右侧那组按钮挪到左上角并裹上玻璃胶囊，右上角只留设置。
///
/// iPad 窄分屏同样会落进 `portraitStack`，但它不该跟着手机改摆法 —— 所以这里除了摆法
/// 还要看 `isPhone`。
public enum PlayerPhoneChromePolicy {

    /// 是否走手机竖屏那套：中央三键换成上一集 / 下一集，倍速进设置菜单，右下角只留全屏键。
    public static func usesPhonePortraitChrome(mode: PlayerLayoutMode, isPhone: Bool) -> Bool {
        isPhone && mode == .portraitStack
    }

    /// 是否走手机横屏那套：顶栏按钮组移到左上角的玻璃胶囊里，设置键留在右上角。
    public static func usesPhoneLandscapeChrome(mode: PlayerLayoutMode, isPhone: Bool) -> Bool {
        isPhone && mode == .immersive
    }
}
