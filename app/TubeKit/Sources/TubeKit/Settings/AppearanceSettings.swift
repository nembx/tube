import SwiftUI

/// 外观设置：跟随系统 / 浅色 / 深色。
///
/// 直接喂给根视图的 `preferredColorScheme` —— 窄屏与宽屏两套 UI 都从
/// `@Environment(\.colorScheme)` 取色，所以一处切换全 App 生效。
public enum AppearanceSettings {
    public static let modeKey = "tube.appearance.mode"

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        public var systemImage: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max"
            case .dark: return "moon"
            }
        }

        /// `nil` 表示跟随系统。
        public var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    public static func mode(from defaults: UserDefaults = .standard) -> Mode {
        defaults.string(forKey: modeKey).flatMap(Mode.init(rawValue:)) ?? .system
    }
}
