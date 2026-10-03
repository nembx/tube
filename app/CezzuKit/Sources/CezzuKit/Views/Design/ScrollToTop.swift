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
    public static let buttonDiameter: CGFloat = 48

    /// 给定偏移量下要不要露出按钮。
    public static func shouldShow(offset: CGFloat, threshold: CGFloat = threshold) -> Bool {
        offset > threshold
    }
}

/// `scrollTo` 的目标 id。
private let scrollToTopAnchorID = "cezzu.scroll-to-top.anchor"

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
        alignment: Alignment = .bottomTrailing
    ) -> some View {
        modifier(ScrollToTopModifier(threshold: threshold, alignment: alignment))
    }
}

/// 包住滚动容器，滚过阈值时在角上浮出回到顶部的玻璃圆钮。
private struct ScrollToTopModifier: ViewModifier {
    let threshold: CGFloat
    let alignment: Alignment

    @State private var offset: CGFloat = 0

    private var isVisible: Bool {
        ScrollToTopLayout.shouldShow(offset: offset, threshold: threshold)
    }

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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
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
                offset = newValue
            }
        } else {
            content.onPreferenceChange(ScrollToTopOffsetKey.self) { newValue in
                offset = newValue
            }
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
                .foregroundStyle(CezzuMonochrome.fill(for: colorScheme))
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
