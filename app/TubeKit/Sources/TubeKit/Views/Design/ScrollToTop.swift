import SwiftUI

/// 「回到顶部」共享零件。
///
/// 长列表滚过几屏之后，靠手指一路往回滑代价太大。用法两步：
///   1. 滚动内容的最顶端放一个 `ScrollToTopAnchor()`
///   2. 滚动容器上挂 `.scrollToTop()`
///
/// 锚点既是偏移量探针，也是 `scrollTo` 的目标，所以必须是内容里的第一个元素。
public enum ScrollToTopLayout {
    /// 内容顶端离开视口这么远（pt）才浮出按钮。约等于半屏，避免刚滑一点就冒出来。
    public static let threshold: CGFloat = 400

    /// 圆钮直径 —— 整圆都是命中区，不小于系统 44pt 最小触控目标。
    /// 与 iOS 26 dock 收合后那颗圆钮同尺寸，两颗并排时才像一对。
    public static let buttonDiameter: CGFloat = 48

    /// 镜像 dock 圆钮时的落点（iPhone 17 / iOS 26 模拟器实测）：收合后的圆钮直径 48，
    /// 圆心离屏幕侧边 52pt、离内容安全区底边往下 31pt。按钮按这两个数镜像到另一侧。
    public static let dockCircleCenterEdgeInset: CGFloat = 52
    public static let dockCircleCenterBelowSafeArea: CGFloat = 31

    /// 不镜像 dock 时按钮离角落的留白。
    public static let cornerHorizontalPadding: CGFloat = 20
    public static let cornerVerticalPadding: CGFloat = 24

    /// 给定偏移量下要不要露出按钮。
    public static func shouldShow(offset: CGFloat, threshold: CGFloat = threshold) -> Bool {
        offset > threshold
    }
}

/// 按钮什么时候露面。
public enum ScrollToTopReveal: Sendable {
    /// 滚过阈值就一直挂着。
    case pastThreshold
    /// 滚过阈值、**且正在往下滚**才露面，手指往回一走就收起来。
    ///
    /// 主页要的是这个：iOS 26 的 dock 向下滚收成一颗圆钮、向上滚再展开，
    /// 按钮跟着这个节奏走 —— dock 缩起来时它才冒头，dock 展开时让位。
    /// 老系统的 dock 不收合，就只按滚动方向走。
    case whileScrollingDown
}

/// 露不露面的状态机。
///
/// 方向这层判断抽出来是为了能单测：`ViewModifier` 里的 `@State` 进不了测试。
public struct ScrollToTopVisibility: Equatable, Sendable {
    /// 翻方向要攒够的位移（pt）。List 的回弹、行高变化带来的零碎位移不该翻方向。
    static let directionSlop: CGFloat = 6

    private let threshold: CGFloat
    private let reveal: ScrollToTopReveal
    /// 当前方向上走过的最远点，用来算位移够不够翻方向。
    private var anchorOffset: CGFloat = 0

    public private(set) var isVisible: Bool = false

    public init(reveal: ScrollToTopReveal, threshold: CGFloat = ScrollToTopLayout.threshold) {
        self.reveal = reveal
        self.threshold = threshold
    }

    /// 每帧滚动都喂进来；视图只读 `isVisible`。
    public mutating func update(offset: CGFloat) {
        guard offset > threshold else {
            // 回到阈值以内（含橡皮筋拉过头的负值）一律收起。锚点跟着走，
            // 免得再往下滚时先要补掉上一次拉过头的位移才露面。
            isVisible = false
            anchorOffset = offset
            return
        }

        guard reveal == .whileScrollingDown else {
            isVisible = ScrollToTopLayout.shouldShow(offset: offset, threshold: threshold)
            anchorOffset = offset
            return
        }

        let delta = offset - anchorOffset
        if delta >= Self.directionSlop {
            isVisible = true
            anchorOffset = offset
        } else if delta <= -Self.directionSlop {
            isVisible = false
            anchorOffset = offset
        } else {
            // 没攒够容差：顺方向的小步位移推着锚点走，反向的先攒着。
            anchorOffset = isVisible ? max(anchorOffset, offset) : min(anchorOffset, offset)
        }
    }
}

/// `scrollTo` 的目标 id。
private let scrollToTopAnchorID = "tube.scroll-to-top.anchor"

/// 内容顶端到视口顶端的距离（正值 = 已往下滚了这么多）。
///
/// 锚点所在的行被回收时（LazyVStack / List 卸载屏外行）没有子视图上报，
/// 退回 `greatestFiniteMagnitude` —— 语义是「顶端早看不见了」，按钮照样该在。
struct ScrollToTopOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 放在滚动内容最顶端的零高锚点。
public struct ScrollToTopAnchor: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: ScrollToTopOffsetKey.self,
                    value: -geo.frame(in: .scrollView(axis: .vertical)).minY
                )
        }
        .frame(height: 0)
        .id(scrollToTopAnchorID)
    }
}

extension View {
    /// 给滚动容器挂上「回到顶部」：滚过阈值时右下角浮出玻璃圆钮。
    /// 内容最顶端必须有一个 `ScrollToTopAnchor()`，否则按钮永远不出现。
    public func scrollToTop(
        threshold: CGFloat = ScrollToTopLayout.threshold,
        alignment: Alignment = .bottomTrailing,
        reveal: ScrollToTopReveal = .pastThreshold
    ) -> some View {
        modifier(ScrollToTopModifier(threshold: threshold, alignment: alignment, reveal: reveal))
    }
}

/// 包住滚动容器，滚过阈值时在角上浮出回到顶部的玻璃圆钮。
private struct ScrollToTopModifier: ViewModifier {
    let threshold: CGFloat
    let alignment: Alignment
    let reveal: ScrollToTopReveal

    @State private var visibility: ScrollToTopVisibility

    init(threshold: CGFloat, alignment: Alignment, reveal: ScrollToTopReveal) {
        self.threshold = threshold
        self.alignment = alignment
        self.reveal = reveal
        _visibility = State(
            initialValue: ScrollToTopVisibility(reveal: reveal, threshold: threshold)
        )
    }

    private var isVisible: Bool { visibility.isVisible }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            tracked(content)
                .overlay(alignment: alignment) {
                    if isVisible {
                        ScrollToTopButton {
                            withAnimation(.easeOut(duration: 0.35)) {
                                proxy.scrollTo(scrollToTopAnchorID, anchor: .top)
                            }
                        }
                        .modifier(ScrollToTopPlacement(reveal: reveal))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isVisible)
        }
    }

    /// 量滚动偏移量。系统给得出 scroll geometry 就直接问系统 —— 比锚点探针准，
    /// 也不会因为锚点所在的行被回收而失真；老平台才回落到探针上报的 preference。
    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                visibility.update(offset: newValue)
            }
        } else {
            content.onPreferenceChange(ScrollToTopOffsetKey.self) { newValue in
                visibility.update(offset: newValue)
            }
        }
    }
}

/// 按钮落在角上的哪个位置。
///
/// 跟着 dock 收合走的那种（`.whileScrollingDown`）在 iOS 26 上要和收合后的圆钮
/// 同一行：圆钮在左下，按钮镜像到右下 —— 圆心等高、离边等距、直径一样，
/// 一左一右像一对。按钮因此探出内容安全区、压进 dock 那一行；收合后那一行右侧
/// 是空的，系统 dock 也不拦这里的点击。老系统 dock 不收合，按钮照旧浮在角落。
private struct ScrollToTopPlacement: ViewModifier {
    let reveal: ScrollToTopReveal

    private var mirrorsDock: Bool {
        #if os(iOS)
            if #available(iOS 26.0, *) { return reveal == .whileScrollingDown }
        #endif
        return false
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if mirrorsDock {
            // 用 padding + offset 而不是 alignmentGuide：按钮外面还套着 `if` 和
            // transition，guide 传不到 overlay 的对齐层，实测会被忽略。
            let radius = ScrollToTopLayout.buttonDiameter / 2
            content
                .padding(.horizontal, ScrollToTopLayout.dockCircleCenterEdgeInset - radius)
                .offset(y: ScrollToTopLayout.dockCircleCenterBelowSafeArea + radius)
        } else {
            content
                .padding(.horizontal, ScrollToTopLayout.cornerHorizontalPadding)
                .padding(.vertical, ScrollToTopLayout.cornerVerticalPadding)
        }
    }
}

/// 玻璃圆钮本体。
///
/// 玻璃背景和 `contentShape` 都在 label 里面：加在 Button 外面的话可点区域只剩
/// icon 本身，水滴的空白处会把点击透传给下层。
struct ScrollToTopButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    /// 每次点击自增，驱动一次轻震。
    @State private var tapCount: Int = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TubeMonochrome.fill(for: colorScheme))
                .frame(width: ScrollToTopLayout.buttonDiameter, height: ScrollToTopLayout.buttonDiameter)
                .glassBackground(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(ScrollToTopButtonStyle())
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: tapCount)
        .accessibilityLabel("回到顶部")
    }
}

/// 按下时整颗水滴缩一下 —— 老平台没有 interactive 玻璃，靠这个给出手感。
private struct ScrollToTopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
