import SwiftUI

/// 宽屏外壳的一级入口。取代原来的 sidebar —— 这些入口现在悬浮嵌在页面顶部。
public enum RegularShellTab: Hashable, CaseIterable, Identifiable, Sendable {
    case home, follow, search, settings

    public var id: Self { self }

    /// 顶栏中间那组文字入口。
    public static var primary: [RegularShellTab] { [.home, .follow] }

    /// 右端那组只留图标的入口。
    public static var trailing: [RegularShellTab] { [.search, .settings] }

    public var label: String {
        switch self {
        case .home: return "主页"
        case .follow: return "追番"
        case .search: return "搜索"
        case .settings: return "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "play.rectangle"
        case .follow: return "star"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }

    /// 选中态用实心图标；搜索没有实心变体。
    public var selectedSystemImage: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .follow: return "star.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }

    /// 自带整幅头图的页面要顶到窗口最上沿，否则标题栏那一条会露出外壳的纯色底、
    /// 和头图拼出一条硬边；其余页面给顶栏让位即可。
    public var extendsUnderTopBar: Bool {
        self == .home || self == .follow
    }
}

/// 宽屏外壳的一级页状态。
///
/// 一级页建过就一直留在视图树里（只是被切走的那几页不显示），切回来不用重新
/// 铺一遍版 —— 「切到搜索 / 主页要等一下」就是每次重建整棵页面树等出来的。
/// 没访问过的入口不预先建，首次进入该等还是等。
struct RegularShellPages: Hashable {
    private(set) var current: RegularShellTab = .home
    private(set) var visited: Set<RegularShellTab> = [.home]
    /// 设置页的代次。
    ///
    /// 设置是唯一用 `NavigationLink { … }` 压二级页的一级页，那种 push 不进
    /// `path`，清空 `path` 弹不掉它 —— 只能把设置页本身换一代，连着它压上去的
    /// 二级页一起拆掉。它本身很轻，重建不心疼。
    private(set) var settingsGeneration: Int = 0

    mutating func select(_ tab: RegularShellTab) {
        if current == .settings || tab == .settings { settingsGeneration += 1 }
        current = tab
        visited.insert(tab)
    }

    func isActive(_ tab: RegularShellTab) -> Bool { tab == current }
}

/// 这一页当前是不是在前台。
///
/// 留在视图树里但被切走的页不该继续跑轮播这类循环动画 —— 看不见，还照样重绘。
extension EnvironmentValues {
    @Entry public var regularShellPageIsActive: Bool = true
}

/// 顶栏落在哪一行。
///
/// macOS 用 `.hiddenTitleBar`，窗口顶部那条安全区是**装饰性**的 —— 交通灯和
/// NavigationStack 的返回按钮都住在里面。顶栏排在安全区下方就会比返回按钮低一行，
/// 压到页面内容上（设置页最明显）。所以 Mac 上要让它升进那一条，和返回按钮同行。
///
/// iPad 的顶部安全区是状态栏 / 灵动岛，不能占。两者没法从 SwiftUI 侧区分，
/// 按 AGENTS.md §3.1 把分叉关在 App target 入口，用这个环境值传进来。
public enum RegularTopBarPlacement: Sendable {
    /// 排在顶部安全区**下方**（iPad 默认）。
    case belowSafeArea
    /// 升进顶部安全区，与返回按钮 / 交通灯同一行（macOS）。
    case inTitleBar
}

extension EnvironmentValues {
    @Entry public var regularTopBarPlacement: RegularTopBarPlacement = .belowSafeArea
}

enum RegularShellLayout {
    static let barHeight: CGFloat = 52
    static let barTopPadding: CGFloat = 12
    /// 左侧让开 macOS 交通灯；宽屏上这段留白读起来像版式，不像躲让。
    static let barLeadingInset: CGFloat = 96
    static let barTrailingInset: CGFloat = 28
    static let itemSpacing: CGFloat = 2
    /// 顶栏后面的黑色渐变。它要一路盖到窗口最上沿（标题栏区域也归它管），
    /// 否则交通灯那一条会露出没压暗的原图。
    static let scrimHeight: CGFloat = 190

    /// 不铺到顶栏下方的页面要让出的高度。
    ///
    /// `inTitleBar` 时顶栏整条都待在安全区里，安全区本身已经把内容推下去了，
    /// 再让一次就会多出一大块空白。
    static func contentTopInset(for placement: RegularTopBarPlacement) -> CGFloat {
        switch placement {
        case .belowSafeArea: return barHeight + barTopPadding * 2
        case .inTitleBar: return 0
        }
    }

    /// 影院底色 —— 不是纯黑，留一点点冷调，避免和封面色块拼出死黑边。
    static let cinemaBackground = Color(red: 0.035, green: 0.035, blue: 0.043)
}

/// 悬浮在内容之上的一级导航。没有背景板，只有一层自上而下的渐变压暗，
/// 所以它在全幅 banner 上是"贴上去"的，不是又一条工具栏。
struct RegularTopBar: View {
    let selected: RegularShellTab
    var onSelect: (RegularShellTab) -> Void

    @Environment(\.regularTopBarPlacement) private var placement

    /// `inTitleBar` 时贴着窗口最上沿排，让胶囊组的中线落在交通灯 / 返回按钮那一行。
    private var topPadding: CGFloat {
        placement == .inTitleBar ? 0 : RegularShellLayout.barTopPadding
    }

    var body: some View {
        // 胶囊组要对齐**窗口**中线。它必须独立于两端那对不对称的内缩
        // （左边要让开交通灯）叠上去，否则中点会被挤到右边去。
        ZStack(alignment: .top) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                ForEach(RegularShellTab.trailing) { tab in
                    iconItem(tab)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, RegularShellLayout.barLeadingInset)
            .padding(.trailing, RegularShellLayout.barTrailingInset)
            .frame(height: RegularShellLayout.barHeight)
            .padding(.top, topPadding)

            GlassContainer(spacing: 6) {
                HStack(spacing: RegularShellLayout.itemSpacing) {
                    ForEach(RegularShellTab.primary) { tab in
                        item(tab)
                    }
                }
                .padding(4)
                .glassBackground(in: Capsule(style: .continuous))
            }
            .frame(height: RegularShellLayout.barHeight)
            .padding(.top, topPadding)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { scrim }
        // Mac 上要盖住标题栏那一条才能和返回按钮同行；iPad 上不能占状态栏。
        .ignoresSafeArea(edges: placement == .inTitleBar ? .top : [])
    }

    /// 顶到窗口最上沿 —— 顶栏本身排在安全区里，但它的压暗层要盖住标题栏那一条。
    private var scrim: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.62),
                .black.opacity(0.26),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: RegularShellLayout.scrimHeight)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private func item(_ tab: RegularShellTab) -> some View {
        let isSelected = tab == selected
        Button {
            onSelect(tab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.footnote.weight(.semibold))
                Text(tab.label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.86))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(.white)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    @ViewBuilder
    private func iconItem(_ tab: RegularShellTab) -> some View {
        let isSelected = tab == selected
        Button {
            onSelect(tab)
        } label: {
            Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.86))
                .frame(width: 36, height: 36)
                .background {
                    if isSelected {
                        Circle().fill(.white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Circle())
        .help(tab.label)
        .accessibilityLabel(tab.label)
    }
}
