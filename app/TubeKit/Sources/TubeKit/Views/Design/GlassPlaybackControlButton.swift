import SwiftUI

public struct GlassPlaybackControlButton: View {
    public enum Prominence {
        case primary
        case secondary
    }

    private let systemImage: String
    private let accessibilityLabel: String
    private let prominence: Prominence
    private let action: () -> Void

    public init(
        systemImage: String,
        accessibilityLabel: String,
        prominence: Prominence = .secondary,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.prominence = prominence
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(iconFont.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .glassBackground(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var diameter: CGFloat {
        switch prominence {
        case .primary:
            86
        case .secondary:
            64
        }
    }

    private var iconFont: Font {
        switch prominence {
        case .primary:
            .largeTitle
        case .secondary:
            .title2
        }
    }
}
