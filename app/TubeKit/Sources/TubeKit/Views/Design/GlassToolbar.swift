import SwiftUI

/// 顶部 / 底部玻璃 toolbar。统一阴影与圆角，让 5 个核心屏的 toolbar 视觉一致。
public struct GlassToolbar<Content: View>: View {
    private let content: Content
    private let edge: HorizontalAlignment

    public init(edge: HorizontalAlignment = .leading, @ViewBuilder content: () -> Content) {
        self.edge = edge
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(in: Capsule())
    }
}
