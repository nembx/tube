import SwiftUI

/// 「继续观看」横向卡布局：卡片就是一张 16:9 封面，标题与进度压在图上。
enum ContinueWatchingLayout {
    static let cardWidth: CGFloat = 228
    /// width / height = 16:9。
    static let coverAspectRatio: CGFloat = 16.0 / 9.0
    static let cardSpacing: CGFloat = 12
    static let coverCornerRadius: CGFloat = 12
    /// 封面底部渐变从底沿往上铺这么大一块，白字压在上面才立得住。
    static let overlayHeightRatio: CGFloat = 0.85
    /// 压图文字的四周内边距。
    static let overlayPadding: CGFloat = 10
    /// 标题与副信息之间的行距。
    static let overlaySpacing: CGFloat = 3

    static var coverHeight: CGFloat {
        cardWidth / coverAspectRatio
    }

    /// 卡片高度就是封面 —— 标题与进度压在图上，不再单独占一条。
    static var cardHeight: CGFloat {
        coverHeight
    }

    /// 副信息行：「第 3 集 · 看到 12:34」。没看过（0ms）只报集数。
    static func metaText(episodeIndex: Int, positionMs: Int) -> String {
        let episode = "第 \(episodeIndex + 1) 集"
        guard positionMs > 0 else { return episode }
        return "\(episode) · 看到 \(positionText(ms: positionMs))"
    }

    /// 进度时间：不足一小时「12:34」，超过一小时「1:02:42」。
    static func positionText(ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// 首页「继续观看」分区：横向滚动最近观看条目，点击进入详情续播。
public struct ContinueWatchingSection: View {
    let entries: [WatchHistoryEntry]
    /// 标题旁边那行拉丁副标题。只有宽屏会给，窄屏传 nil 保持原样。
    let subtitle: String?
    var onTapEntry: (WatchHistoryEntry) -> Void
    var onRemoveEntry: (WatchHistoryEntry) -> Void
    /// 本地帧封面丢了时用的番剧海报；没有就显示占位。
    var fallbackCoverURL: (WatchHistoryEntry) -> URL?
    /// 卡片发现本地帧丢了，请上层去把海报找回来。
    var onNeedsFallbackCover: (WatchHistoryEntry) -> Void

    public init(
        entries: [WatchHistoryEntry],
        subtitle: String? = nil,
        onTapEntry: @escaping (WatchHistoryEntry) -> Void,
        onRemoveEntry: @escaping (WatchHistoryEntry) -> Void,
        fallbackCoverURL: @escaping (WatchHistoryEntry) -> URL? = { _ in nil },
        onNeedsFallbackCover: @escaping (WatchHistoryEntry) -> Void = { _ in }
    ) {
        self.entries = entries
        self.subtitle = subtitle
        self.onTapEntry = onTapEntry
        self.onRemoveEntry = onRemoveEntry
        self.fallbackCoverURL = fallbackCoverURL
        self.onNeedsFallbackCover = onNeedsFallbackCover
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
                            ContinueWatchingCard(
                                entry: entry,
                                fallbackCoverURL: fallbackCoverURL(entry),
                                onNeedsFallbackCover: { onNeedsFallbackCover(entry) }
                            )
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

/// 继续观看横卡：一张 16:9 封面（优先当前帧截图），标题与「第 N 集 · 看到 mm:ss」
/// 压在底部渐变上 —— 卡片就是一张图，白字直接落在画面上。
struct ContinueWatchingCard: View {
    let entry: WatchHistoryEntry
    var fallbackCoverURL: URL? = nil
    var onNeedsFallbackCover: () -> Void = {}

    @State private var isHovering: Bool = false

    var body: some View {
        cover
            .offset(y: isHovering ? -BangumiCardLayout.hoverLift : 0)
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isHovering)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.bangumiTitle)，\(metaText)")
            .task(id: entry.coverURLString) {
                // 本地帧按当前容器找不到（重装 / 更新后路径变了）→ 去拿番剧海报。
                if HistoryStore.resolvedCoverURL(for: entry.coverURLString) == nil {
                    onNeedsFallbackCover()
                }
            }
    }

    private var metaText: String {
        ContinueWatchingLayout.metaText(
            episodeIndex: entry.lastEpisodeIndex,
            positionMs: entry.lastPositionMs
        )
    }

    /// 封面地址，以及它是本地帧（16:9，铺满裁切）还是海报（竖版，居中留边）。
    private var resolvedCover: (url: URL?, letterboxed: Bool) {
        if HistoryStore.isLocalFrameCover(entry.coverURLString) {
            let frame = HistoryStore.resolvedCoverURL(for: entry.coverURLString)
            if let frame {
                return (frame, false)
            }
        }
        return (HistoryStore.resolvedCoverURL(for: entry.coverURLString) ?? fallbackCoverURL, true)
    }

    @ViewBuilder
    private var cover: some View {
        let shape = RoundedRectangle(
            cornerRadius: ContinueWatchingLayout.coverCornerRadius,
            style: .continuous
        )
        Color.clear
            .frame(width: ContinueWatchingLayout.cardWidth, height: ContinueWatchingLayout.coverHeight)
            .background { Color.secondary.opacity(0.08) }
            .overlay {
                coverContent
                    .scaleEffect(isHovering ? BangumiCardLayout.hoverImageScale : 1)
                    .clipped()
            }
            .overlay(alignment: .bottom) { textOverlay }
            .clipShape(shape)
            .contentShape(shape)
            .shadow(
                color: .black.opacity(isHovering ? 0.55 : 0),
                radius: isHovering ? 18 : 0,
                y: isHovering ? 10 : 0
            )
    }

    @ViewBuilder
    private var coverContent: some View {
        let resolved = resolvedCover
        if resolved.letterboxed {
            posterCover(url: resolved.url)
        } else {
            frameCover(url: resolved.url)
        }
    }

    /// 16:9 帧：铺满整卡。
    @ViewBuilder
    private func frameCover(url: URL?) -> some View {
        RemoteImage(url: url) {
            placeholder
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 竖版海报：按高摆中间，两侧是同一张图放大模糊的兜底 —— 直接裁成
    /// 16:9 横条会把脸裁掉一半，这是帧丢失（重装 / 更新）后的常见样子。
    @ViewBuilder
    private func posterCover(url: URL?) -> some View {
        ZStack {
            RemoteImage(url: url) { Color.clear }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 24, opaque: true)
                .overlay(Color.black.opacity(0.35))
            RemoteImage(url: url) { placeholder }
                .frame(
                    width: ContinueWatchingLayout.coverHeight * BangumiCardLayout.coverAspectRatio,
                    height: ContinueWatchingLayout.coverHeight
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 标题 + 「第 N 集 · 看到 mm:ss」压在封面底部；背后垫一层渐变保证可读性。
    @ViewBuilder
    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: ContinueWatchingLayout.overlaySpacing) {
            Text(entry.bangumiTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(metaText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.82))
        }
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .padding(ContinueWatchingLayout.overlayPadding)
        .frame(width: ContinueWatchingLayout.cardWidth, alignment: .leading)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.28), location: 0.35),
                    .init(color: .black.opacity(0.6), location: 0.7),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: ContinueWatchingLayout.coverHeight * ContinueWatchingLayout.overlayHeightRatio)
        }
        .allowsHitTesting(false)
    }
}
