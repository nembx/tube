import SwiftUI

// MARK: - Monochrome chrome（全平台共用）

/// 黑白 monochrome 主色：浅色黑 / 深色白。
/// 主行动按钮、选中 chip、详情播放等共用，避免业务层各自猜对比色。
public enum CezzuMonochrome {
    /// 填充色：浅色黑、深色白。
    public static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
    }

    /// 填充上的前景（反色）：浅色白字、深色黑字。
    public static func onFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : .white
    }
}

/// Toggle 专用 tint：浅色保持 monochrome 黑，深色恢复系统蓝（不被全局白/黑 accent 盖掉）。
public struct CezzuToggleTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content.tint(colorScheme == .dark ? Color.blue : Color.primary)
    }
}

extension View {
    /// 给 Toggle 套上「浅色黑 / 深色蓝」的 active 色。
    public func cezzuToggleTint() -> some View {
        modifier(CezzuToggleTint())
    }
}

/// 主行动按钮 —— monochrome 胶囊：深色白底黑字，浅色黑底白字。
/// 不依赖系统 `.glassProminent` / accent 的自动前景色（深色白 accent 会渲成白底白字）。
public struct GlassPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(CezzuMonochrome.onFill(for: colorScheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                CezzuMonochrome.fill(for: colorScheme),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .controlSize(.large)
    }
}

/// 次级按钮 —— iOS 26+ 走 `.buttonStyle(.glass)`，老平台回落到 `.bordered`。
public struct GlassSecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .padding(.horizontal, 6)
        }
        .modifier(GlassButtonStyle())
        .controlSize(.regular)
    }
}

// MARK: - 兼容层 modifier

private struct GlassButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
