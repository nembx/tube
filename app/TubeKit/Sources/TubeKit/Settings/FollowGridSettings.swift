import Foundation

/// 追番页宫格密度：三列（默认）或两列。
///
/// 只作用于窄屏 `FollowView` 的固定列数宫格 —— 宽屏 `RegularFollowView`
/// 的宫格本来就按容器宽度自适应列数，不需要这档开关。
public enum FollowGridDensity: String, CaseIterable, Identifiable, Sendable {
    case three
    case two

    public var id: String { rawValue }

    /// 窄屏宫格的列数。
    public var columnCount: Int {
        switch self {
        case .three: return 3
        case .two: return 2
        }
    }

    public var label: String {
        switch self {
        case .three: return "三列"
        case .two: return "两列"
        }
    }

    /// 图标画的正是当前列数，一眼能看出宫格现在是几列。
    public var systemImage: String {
        switch self {
        case .three: return "square.grid.3x3"
        case .two: return "square.grid.2x2"
        }
    }

    /// 点一下切到另一档。
    public var toggled: FollowGridDensity {
        switch self {
        case .three: return .two
        case .two: return .three
        }
    }
}

/// 追番页宫格密度设置（`tube.follow.gridDensity`）。
///
/// 与 `AppearanceSettings` 一样存 UserDefaults 裸值，视图侧用 `@AppStorage` 绑定，
/// 这里只负责解析与默认值。
public enum FollowGridSettings {
    public static let densityKey = "tube.follow.gridDensity"
    /// 默认三列 —— 加开关之前窄屏就是 3 列，老用户升级后版式不变。
    public static let densityDefault: FollowGridDensity = .three

    public static func density(from defaults: UserDefaults = .standard) -> FollowGridDensity {
        defaults.string(forKey: densityKey).flatMap(FollowGridDensity.init(rawValue:)) ?? densityDefault
    }
}
