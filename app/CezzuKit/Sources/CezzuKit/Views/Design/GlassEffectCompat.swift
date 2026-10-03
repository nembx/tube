import SwiftUI

/// Liquid Glass 兼容层 —— CezzuKit 里**唯一**允许直接接触 `glassEffect()` 的地方。
///
/// 业务代码、Glass* 组件都通过这里的两个入口拿玻璃效果：
///   1. `View.glassBackground(in:tint:)` —— 给任意 view 套玻璃背景
///   2. `GlassContainer { ... }` —— iOS 26 形态过渡容器；老平台是透明 passthrough
///
/// 在 iOS 26 / macOS 26 上走真正的 Liquid Glass API；在 iOS 17-25 / macOS 14-25
/// 上回落到 SwiftUI `Material`（`.ultraThinMaterial`）。视觉差异肉眼可辨，但
/// 整体设计语言一致，不会有"裂"的感觉。

extension View {
    /// 给当前 view 加一层玻璃背景。形状自定义，可选 tint。
    ///
    /// - Parameters:
    ///   - shape: 玻璃区域的形状（`Capsule()` / `RoundedRectangle(...)` / 任意 Shape）
    ///   - tint: 可选染色，用于"选中态"高亮。`nil` = 纯玻璃。
    ///   - interactive: 玻璃跟手 —— 按下时整块玻璃会缩放、折射跟着走。只给可点的元件开。
    public func glassBackground<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> AnyView {
        #if targetEnvironment(simulator)
            return AnyView(self.background(MaterialFallback(shape: shape, tint: tint)))
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            var glass: Glass = .regular
            if let tint {
                glass = glass.tint(tint)
            }
            if interactive {
                glass = glass.interactive()
            }
            return AnyView(self.glassEffect(glass, in: shape))
        } else {
            return AnyView(self.background(MaterialFallback(shape: shape, tint: tint)))
        }
        #endif
    }
}

/// `GlassEffectContainer` 的兼容包装。iOS 26 上是真容器，做形态过渡调度；
/// 更老平台是无副作用的 passthrough。
public struct GlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - private fallback view

/// iOS 17-25 / macOS 14-25 的 Material 兜底渲染。
private struct MaterialFallback<S: Shape>: View {
    let shape: S
    let tint: Color?

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            if let tint {
                shape.fill(tint.opacity(0.5))
            }
            shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}
