import SwiftUI

enum BangumiCardLayout {
    static let coverAspectRatio: CGFloat = 3.0 / 4.0
    static let coverCornerRadius: CGFloat = 12
    static let titleHeight: CGFloat = 44
    static let overlayHeightRatio: CGFloat = 0.2
    static let spacing: CGFloat = 6
    /// 指针悬停：整卡上浮这么多，封面在圆角里放大这么多。
    /// 触屏上不会触发，所以窄屏看不到这套效果。
    static let hoverLift: CGFloat = 8
    static let hoverImageScale: CGFloat = 1.08
}

/// 番剧封面卡 —— HomeView 宫格 cell 与 BangumiInfoView header 共用。
///
/// 一张 3:4 比例的封面 + 下方标题。封面底部叠一层渐变元数据。
public struct BangumiCard: View {
    let item: BangumiItem

    @State private var isHovering: Bool = false

    public init(item: BangumiItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BangumiCardLayout.spacing) {
            cover
            Text(item.displayName)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: BangumiCardLayout.titleHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .offset(y: isHovering ? -BangumiCardLayout.hoverLift : 0)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isHovering)
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: item.images.listBest)
        let shape = RoundedRectangle(cornerRadius: BangumiCardLayout.coverCornerRadius, style: .continuous)
        Color.clear
        .frame(maxWidth: .infinity)
        .aspectRatio(BangumiCardLayout.coverAspectRatio, contentMode: .fit)
        .background {
            Color.secondary.opacity(0.08)
        }
        .overlay {
            coverContent(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(isHovering ? BangumiCardLayout.hoverImageScale : 1)
                .clipped()
        }
        .overlay(alignment: .bottom) {
            metaOverlay
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
    private var metaOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 1 - BangumiCardLayout.overlayHeightRatio),
                    .init(color: .black.opacity(0.4), location: 0.9),
                    .init(color: .black.opacity(0.82), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .center, spacing: 4) {
                if item.ratingScore > 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", item.ratingScore))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
    }

    /// 走 `RemoteImage` 而不是 `AsyncImage`：后者的缓存不落盘，
    /// 首页十几个分区来回滚就是几百次重复下载 + 重复解码，肉眼可见地卡。
    @ViewBuilder
    private func coverContent(url: URL?) -> some View {
        RemoteImage(url: url) {
            placeholder(systemImage: "photo")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
