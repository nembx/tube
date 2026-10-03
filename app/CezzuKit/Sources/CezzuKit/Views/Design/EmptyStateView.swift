import SwiftUI

/// 通用空 / 错误状态。SF Symbol 圆形底 + 标题 + 副标题 + 可选行动按钮。
/// 用在首页 / 搜索页 / 详情页等所有"没有内容"的位置。
public struct EmptyStateView: View {
    public enum Tone {
        case neutral
        case warning
        case error

        var iconColor: Color {
            switch self {
            case .neutral: return .secondary
            case .warning: return .orange
            case .error: return .red
            }
        }

        var iconBackground: Color {
            switch self {
            case .neutral: return Color.secondary.opacity(0.12)
            case .warning: return Color.orange.opacity(0.14)
            case .error: return Color.red.opacity(0.14)
            }
        }
    }

    let systemImage: String
    let title: String
    let message: String?
    let tone: Tone
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String? = nil,
        tone: Tone = .neutral,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tone.iconBackground)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(tone.iconColor)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: 280)

            if let actionTitle, let action {
                GlassPrimaryButton(actionTitle, systemImage: "arrow.clockwise", action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }
}
