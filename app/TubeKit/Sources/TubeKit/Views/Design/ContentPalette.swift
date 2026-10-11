import SwiftUI

/// 内容页的配色：详情页、宽屏详情页、播放页详情面板共用一套。
///
/// 底色由封面主色驱动（和首页 banner 呼应），文字层级用固定对比色。
/// `surface` 是**透明叠色**而不是不透明灰：不透明灰在取色底上会读成一块贴上去的
/// 卡片，透明叠色则始终是页面底色自己的深浅。
struct ContentPalette {
    let background: Color
    let backgroundRaised: Color
    let surface: Color
    let surfaceRaised: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let hairline: Color

    static func make(for colorScheme: ColorScheme, cover: CoverColorPalette) -> ContentPalette {
        switch colorScheme {
        case .dark:
            return ContentPalette(
                background: cover.darkened.color,
                backgroundRaised: cover.color.opacity(0.22),
                surface: .white.opacity(0.06),
                surfaceRaised: .white.opacity(0.12),
                textPrimary: .white,
                textSecondary: .white.opacity(0.70),
                textTertiary: .white.opacity(0.48),
                hairline: .white.opacity(0.10)
            )
        default:
            return ContentPalette(
                background: cover.washed.color,
                backgroundRaised: cover.washed.color,
                surface: .black.opacity(0.04),
                surfaceRaised: .black.opacity(0.07),
                textPrimary: Color(red: 0.05, green: 0.05, blue: 0.06),
                textSecondary: Color(red: 0.20, green: 0.21, blue: 0.24),
                textTertiary: Color(red: 0.42, green: 0.43, blue: 0.47),
                hairline: .black.opacity(0.10)
            )
        }
    }
}

extension SourceRailStyle {
    /// 内容页配色下的选源胶囊。
    static func content(_ palette: ContentPalette) -> SourceRailStyle {
        SourceRailStyle(
            textPrimary: palette.textPrimary,
            textSecondary: palette.textSecondary,
            textTertiary: palette.textTertiary,
            selectedFill: palette.surfaceRaised,
            fill: palette.surface,
            hairline: palette.hairline
        )
    }
}
