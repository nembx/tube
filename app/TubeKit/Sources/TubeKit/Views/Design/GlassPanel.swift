import SwiftUI

/// Liquid Glass 通用面板。所有 glass 用法在 v1 都通过这一组封装，便于跟随
/// SwiftUI 的 API 演进。
///
/// 内部走 `glassBackground(in:)` 兼容层：iOS 26 / macOS 26 启用真正的 Liquid
/// Glass，更老平台回落到 `Material`。
public struct GlassPanel<PanelShape: Shape, Content: View>: View {
    private let content: Content
    private let shape: PanelShape

    public init(shape: PanelShape, @ViewBuilder content: () -> Content) {
        self.shape = shape
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .glassBackground(in: shape)
    }
}

extension GlassPanel where PanelShape == RoundedRectangle {
    public init(@ViewBuilder content: () -> Content) {
        self.init(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), content: content)
    }
}

/// 一组玻璃元素的容器，让 iOS 26 上的形态过渡可以统一调度；老平台是 passthrough。
public struct GlassPanelContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassContainer(spacing: 16) {
            content
        }
    }
}
