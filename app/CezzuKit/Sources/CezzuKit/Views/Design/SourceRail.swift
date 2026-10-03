import SwiftUI

extension SourceRailStyle {
    /// 播放页那层深色玻璃上的配色。
    static let playerPanel = SourceRailStyle(
        textPrimary: .white,
        textSecondary: .white.opacity(0.82),
        textTertiary: .white.opacity(0.55),
        selectedFill: .white.opacity(0.22),
        fill: .white.opacity(0.08),
        hairline: .white.opacity(0.18)
    )
}

/// 选源胶囊的配色。三个调用点（窄屏详情 / 宽屏详情 / 播放页切源面板）各自的主题不同，
/// 只把颜色传进来，排版和交互由 `SourceRail` 统一负责。
struct SourceRailStyle {
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let selectedFill: Color
    let fill: Color
    let hairline: Color
}

/// 播放源选择条。
///
/// 同一个站点的多个条目在 `SourceGroup` 里已经合并过，这里一个站点只占一个胶囊：
/// 单条目直接选中，多条目点开 popover 挑。胶囊高度固定，带不带下拉箭头 / 锁都对得齐。
struct SourceRail: View {
    enum ChipLayout {
        /// 宽屏：换行铺满。
        case wrap
        /// 窄屏 / 侧栏：横向滚动一行。
        case scroll
    }

    let groups: [SourceGroup]
    let blockedSources: [BlockedSource]
    let selectedSourceID: PlayableSource.ID?
    let layout: ChipLayout
    let style: SourceRailStyle
    let onSelect: (PlayableSource.ID) -> Void
    let onUnblock: (String) -> Void

    @State private var openGroupID: SourceGroup.ID?
    /// 打开中的那个 popover 里，条目列表的真实高度。用它把 popover 收到内容大小，
    /// 同时不超过 `variantListMaxHeight`。
    @State private var variantListHeight: CGFloat = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let chipHeight: CGFloat = 34
    /// 站点名可以很长，不封顶的话一个胶囊就能吃掉整行。
    private let chipMaxWidth: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch layout {
            case .wrap:
                WrapLayout(spacing: 8, lineSpacing: 8) {
                    chips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .scroll:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chips
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let selected = selectedSource, selected.variantLabel != selected.ruleName {
                Text("当前 · \(selected.variantLabel)")
                    .font(.caption)
                    .foregroundStyle(style.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private var selectedSource: PlayableSource? {
        groups.lazy.flatMap(\.sources).first { $0.id == selectedSourceID }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(groups) { group in
            groupChip(group)
        }
        ForEach(blockedSources) { blocked in
            blockedChip(blocked)
        }
    }

    @ViewBuilder
    private func groupChip(_ group: SourceGroup) -> some View {
        let selected = group.sources.first { $0.id == selectedSourceID }
        Button {
            if group.sources.count == 1, let only = group.sources.first {
                onSelect(only.id)
            } else {
                variantListHeight = 0
                openGroupID = group.id
            }
        } label: {
            chipShell(isSelected: selected != nil, isDashed: false) {
                HStack(spacing: 6) {
                    Text(group.ruleName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if group.sources.count > 1 {
                        Text("\(group.sources.count)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(selected != nil ? style.textSecondary : style.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(style.hairline.opacity(0.6))
                            }
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selected != nil ? style.textSecondary : style.textTertiary)
                    }
                }
                .font(.subheadline.weight(selected != nil ? .semibold : .medium))
                .foregroundStyle(selected != nil ? style.textPrimary : style.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { openGroupID == group.id },
                set: { openGroupID = $0 ? group.id : nil }
            ),
            arrowEdge: .bottom
        ) {
            variantPicker(group)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func blockedChip(_ blocked: BlockedSource) -> some View {
        Button {
            onUnblock(blocked.ruleName)
        } label: {
            chipShell(isSelected: false, isDashed: true) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.caption2.weight(.semibold))
                    Text(blocked.ruleName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(style.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .help("需要验证码，点击完成人机校验")
    }

    /// 所有胶囊共用的外壳：固定高度 + 同样的内边距，保证一行里对得齐。
    @ViewBuilder
    private func chipShell(
        isSelected: Bool,
        isDashed: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .padding(.horizontal, 14)
            .frame(height: chipHeight)
            .frame(maxWidth: chipMaxWidth, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? style.selectedFill : style.fill)
            }
            .overlay {
                if isDashed {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            style.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                } else {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? style.hairline : style.hairline.opacity(0.55),
                            lineWidth: 1
                        )
                }
            }
            .contentShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func variantPicker(_ group: SourceGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 站点名钉在顶上不跟着滚 —— 条目多的时候滚起来还得知道自己在哪个源里。
            Text(group.ruleName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            // 一个站点下几十个资源是常事，不套 ScrollView 的话 popover 会被撑出屏幕，
            // 露不出来的那些条目就再也点不到了。
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.sources) { source in
                        variantRow(source)
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.height, initial: true) { _, height in
                                variantListHeight = height
                            }
                    }
                }
            }
            .frame(height: variantListDisplayHeight(group))
            // 条目装得下时不给回弹，免得短列表也能上下拖。
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.bottom, 8)
        .frame(width: 300)
    }

    @ViewBuilder
    private func variantRow(_ source: PlayableSource) -> some View {
        let isSelected = source.id == selectedSourceID
        Button {
            openGroupID = nil
            onSelect(source.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(source.variantLabel)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 列表区该占多高：贴着内容走，但不超过当前摆向放得下的量。
    ///
    /// 还没量到高度的那一帧用估算值兜底，否则 popover 会先弹出一个一行高的壳
    /// 再撑开，看着像抖了一下。
    private func variantListDisplayHeight(_ group: SourceGroup) -> CGFloat {
        let measured = variantListHeight > 0
            ? variantListHeight
            : SourceRail.estimatedVariantListHeight(sourceCount: group.sources.count)
        return min(measured, variantListMaxHeight)
    }

    /// 横屏手机上 popover 本来就没多少纵向空间，硬撑会被裁掉。
    private var variantListMaxHeight: CGFloat {
        verticalSizeClass == .compact ? 240 : 400
    }

    /// 每行按单行文案估。多行的条目会被低估，但只影响首帧，量到真值就修正了。
    static func estimatedVariantListHeight(sourceCount: Int) -> CGFloat {
        CGFloat(max(sourceCount, 1)) * 38
    }
}
