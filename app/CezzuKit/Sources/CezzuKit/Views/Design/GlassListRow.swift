import SwiftUI

/// 列表行的玻璃样式 —— 用于搜索结果、剧集列表、规则列表。
public struct GlassListRow<Content: View>: View {
    private let content: Content
    private let isSelected: Bool

    public init(isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    public var body: some View {
        HStack {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassBackground(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: isSelected ? Color.accentColor.opacity(0.3) : nil
        )
    }
}
