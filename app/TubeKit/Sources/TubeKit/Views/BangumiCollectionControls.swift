import SwiftUI

/// 详情页的收藏状态菜单：想看 / 在看 / 看过 / 搁置 / 抛弃。
///
/// 只负责行为，外观由调用方的 `label` 决定 —— 窄屏和宽屏详情页按钮长得不一样。
/// 登录后它替掉原来的「追番」星标；匿名时详情页仍用本地星标。
struct BangumiCollectionStatusMenu<Label: View>: View {
    let item: BangumiItem
    @ViewBuilder let label: (BangumiCollectionType?) -> Label
    @Environment(BangumiCollectionStore.self) private var collections

    var body: some View {
        let current = collections.collectionType(for: item)
        Menu {
            ForEach(BangumiCollectionType.allCases, id: \.self) { type in
                Button {
                    Task { await collections.setCollection(type, for: item) }
                } label: {
                    if current == type {
                        SwiftUI.Label(type.label, systemImage: "checkmark")
                    } else {
                        SwiftUI.Label(type.label, systemImage: type.systemImage)
                    }
                }
            }
        } label: {
            label(current)
        }
        .menuIndicator(.hidden)
        .animation(.easeOut(duration: 0.16), value: current)
    }
}

/// 详情页状态按钮的文案与图标。有状态时显示状态名；没有就显示「收藏」。
enum BangumiCollectionButtonStyle {
    static func title(for type: BangumiCollectionType?) -> String {
        type?.label ?? "收藏"
    }

    static func systemImage(for type: BangumiCollectionType?) -> String {
        type?.systemImage ?? "plus.circle"
    }

    /// 状态胶囊的强调色。在看用主题色，看过用绿色，其它用次要色。
    static func tint(for type: BangumiCollectionType?, fallback: Color) -> Color {
        switch type {
        case .doing: return .accentColor
        case .collect: return .green
        case .wish: return .orange
        case .onHold, .dropped: return fallback.opacity(0.7)
        case nil: return fallback
        }
    }
}

/// 剧集格子右上角的小勾：这一集在 bgm 上已标记看过。
struct BangumiEpisodeWatchedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .green)
            .padding(4)
            .accessibilityLabel("已看过")
    }
}

/// 详情页「已看 N / M」进度条文案。
enum BangumiProgressLabel {
    static func text(watched: Int, total: Int) -> String? {
        guard watched > 0 || total > 0 else { return nil }
        if total > 0 {
            return "已看 \(min(watched, total)) / \(total) 集"
        }
        return "已看 \(watched) 集"
    }
}

/// 追番页顶部的状态筛选：全部 / 在看 / 想看 / 看过 / 搁置 / 抛弃。
///
/// 只在登录后出现。计数来自本地收藏里有 bgm 状态的那部分 —— 匿名时期的本地收藏
/// 没有状态，只在「全部」里。
struct BangumiCollectionFilterBar: View {
    @Binding var selected: BangumiCollectionType?
    let items: [BangumiItem]
    /// 胶囊的明暗。宽屏壳恒定深色，窄屏跟随系统。
    var scheme: ColorScheme = .dark
    @Environment(BangumiCollectionStore.self) private var collections

    /// 想看在前面方便「接下来看什么」，搁置 / 抛弃放最后。
    static let order: [BangumiCollectionType?] = [nil, .doing, .wish, .collect, .onHold, .dropped]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(Self.order.enumerated()), id: \.offset) { _, type in
                    let count = count(for: type)
                    if type == nil || count > 0 {
                        chip(type, count: count)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func count(for type: BangumiCollectionType?) -> Int {
        guard let type else { return items.count }
        return items.filter { collections.collectionType(for: $0) == type }.count
    }

    @ViewBuilder
    private func chip(_ type: BangumiCollectionType?, count: Int) -> some View {
        let isSelected = selected == type
        let foreground: Color = scheme == .dark ? .white : .black
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selected = type }
        } label: {
            HStack(spacing: 5) {
                Text(type?.label ?? "全部")
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .opacity(0.7)
            }
            .foregroundStyle(isSelected ? (scheme == .dark ? Color.black : Color.white) : foreground.opacity(0.85))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? foreground : foreground.opacity(0.1))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(foreground.opacity(isSelected ? 0 : 0.14), lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension BangumiCollectionStore {
    /// 追番页按状态过滤。`nil` 表示全部。
    public func filter(_ items: [BangumiItem], by type: BangumiCollectionType?) -> [BangumiItem] {
        guard let type else { return items }
        return items.filter { collectionType(for: $0) == type }
    }
}
