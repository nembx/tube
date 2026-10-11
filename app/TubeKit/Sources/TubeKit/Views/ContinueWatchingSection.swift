import SwiftUI

/// 「继续观看」横向卡布局：宽 > 高，宽高比 16:9（横屏帧 / 截图友好）。
enum ContinueWatchingLayout {
    static let cardWidth: CGFloat = 228
    /// width / height = 16:9。
    static let coverAspectRatio: CGFloat = 16.0 / 9.0
    static let cardSpacing: CGFloat = 12
    static let coverCornerRadius: CGFloat = 12
    static let titleHeight: CGFloat = 40
    static let metaHeight: CGFloat = 18
    static let spacing: CGFloat = 6

    static var coverHeight: CGFloat {
        cardWidth / coverAspectRatio
    }

    static var cardHeight: CGFloat {
        coverHeight + spacing + titleHeight + 2 + metaHeight
    }
}

/// 首页「继续观看」分区：横向滚动最近观看条目，点击进入详情续播。
public struct ContinueWatchingSection: View {
    let entries: [WatchHistoryEntry]
    /// 标题旁边那行拉丁副标题。只有宽屏会给，窄屏传 nil 保持原样。
    let subtitle: String?
    var onTapEntry: (WatchHistoryEntry) -> Void
    var onRemoveEntry: (WatchHistoryEntry) -> Void

    public init(
        entries: [WatchHistoryEntry],
        subtitle: String? = nil,
        onTapEntry: @escaping (WatchHistoryEntry) -> Void,
        onRemoveEntry: @escaping (WatchHistoryEntry) -> Void
    ) {
        self.entries = entries
        self.subtitle = subtitle
        self.onTapEntry = onTapEntry
        self.onRemoveEntry = onRemoveEntry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("继续观看")
                    .font(.title3.bold())
                    .tracking(subtitle == nil ? 0 : 2)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, BangumiSectionLayout.headerBottomPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: ContinueWatchingLayout.cardSpacing) {
                    ForEach(entries) { entry in
                        Button {
                            onTapEntry(entry)
                        } label: {
                            ContinueWatchingCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onTapEntry(entry)
                            } label: {
                                Label("继续观看", systemImage: "play.fill")
                            }
                            Button("移除", role: .destructive) {
                                onRemoveEntry(entry)
                            }
                        }
                    }
                }
                .padding(.top, BangumiCardLayout.hoverLift)
            }
            .frame(
                height: ContinueWatchingLayout.cardHeight + BangumiCardLayout.hoverLift,
                alignment: .top
            )
        }
    }
}

/// 继续观看横卡：16:9 封面（优先当前帧截图）+ 标题 + 集数/进度。
struct ContinueWatchingCard: View {
    let entry: WatchHistoryEntry

    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: ContinueWatchingLayout.spacing) {
            cover
            Text(entry.bangumiTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(
                    width: ContinueWatchingLayout.cardWidth,
                    height: ContinueWatchingLayout.titleHeight,
                    alignment: .topLeading
                )
            Text(metaText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: ContinueWatchingLayout.cardWidth,
                    height: ContinueWatchingLayout.metaHeight,
                    alignment: .leading
                )
        }
        .frame(width: ContinueWatchingLayout.cardWidth, alignment: .topLeading)
        .offset(y: isHovering ? -BangumiCardLayout.hoverLift : 0)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isHovering)
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: entry.coverURLString ?? "")
        let shape = RoundedRectangle(
            cornerRadius: ContinueWatchingLayout.coverCornerRadius,
            style: .continuous
        )
        Color.clear
            .frame(width: ContinueWatchingLayout.cardWidth, height: ContinueWatchingLayout.coverHeight)
            .background { Color.secondary.opacity(0.08) }
            .overlay {
                coverImage(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(isHovering ? BangumiCardLayout.hoverImageScale : 1)
                    .clipped()
            }
            .overlay(alignment: .bottom) {
                progressOverlay
            }
            .clipShape(shape)
            .contentShape(shape)
            .shadow(
                color: .black.opacity(isHovering ? 0.55 : 0),
                radius: isHovering ? 18 : 0,
                y: isHovering ? 10 : 0
            )
    }

    @ViewBuilder
    private func coverImage(url: URL?) -> some View {
        RemoteImage(url: url) {
            ZStack {
                Color.secondary.opacity(0.08)
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: ContinueWatchingLayout.coverHeight * 0.42)

            HStack {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                Text(positionLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                Spacer(minLength: 4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
    }

    private var metaText: String {
        let episode = "第 \(entry.lastEpisodeIndex + 1) 集"
        if entry.lastEpisodeTitle.isEmpty {
            return episode
        }
        return "\(episode) · \(entry.lastEpisodeTitle)"
    }

    private var positionLabel: String {
        guard entry.lastPositionMs > 0 else { return "继续" }
        let totalSeconds = entry.lastPositionMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
