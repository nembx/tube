import SwiftUI

/// 播放器悬浮控制条。整层套玻璃背景，并在 iOS 26 上用 `glassEffectID` 做出现 /
/// 消失的形态过渡（更老平台直接渲染，不做过渡）。
public struct GlassPlayerControls<Leading: View, Center: View, Trailing: View>: View {
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing
    @Namespace private var namespace

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    public var body: some View {
        GlassContainer(spacing: 12) {
            HStack(spacing: 12) {
                leading
                Spacer()
                center
                Spacer()
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .modifier(PlayerControlsGlassID(namespace: namespace))
        }
    }
}

/// `glassEffectID` 在 iOS 26 才有；这里 isolate 起来用 if-available 包住。
private struct PlayerControlsGlassID: ViewModifier {
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffectID("player-controls", in: namespace)
        } else {
            content
        }
    }
}
