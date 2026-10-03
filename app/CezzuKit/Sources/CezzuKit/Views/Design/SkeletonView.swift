import SwiftUI

/// 通用 shimmer 占位块。一个浅色填充矩形，上面叠一层 1.4s 循环扫过的高光。
/// 业务层不直接用这个，用 `BangumiCardSkeleton` / `BangumiSkeletonGrid`。
struct ShimmerBlock: View {
    var cornerRadius: CGFloat = 8
    @State private var phase: CGFloat = -1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { geo in
            shape
                .fill(Color.secondary.opacity(0.14))
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0.0),
                            .init(color: .white.opacity(0.30), location: 0.5),
                            .init(color: .white.opacity(0), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * (geo.size.width + geo.size.width * 0.5))
                )
                .clipShape(shape)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// 一个番剧卡尺寸的骨架占位 —— 3:4 封面 + 两行标题。布局严格对齐 BangumiCard。
public struct BangumiCardSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: BangumiCardLayout.spacing) {
            ShimmerBlock(cornerRadius: BangumiCardLayout.coverCornerRadius)
                .aspectRatio(BangumiCardLayout.coverAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerBlock(cornerRadius: 4)
                    .frame(height: 11)
                ShimmerBlock(cornerRadius: 4)
                    .frame(width: 90, height: 11)
            }
            .frame(height: BangumiCardLayout.titleHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 番剧宫格的骨架版本。和 `BangumiGrid` 共用 `BangumiGridLayout.columns`，渲染 N 个占位卡。
public struct BangumiSkeletonGrid: View {
    private let placeholderCount: Int

    public init(placeholderCount: Int = 8) {
        self.placeholderCount = placeholderCount
    }

    public var body: some View {
        LazyVGrid(
            columns: BangumiGridLayout.columns,
            alignment: .leading,
            spacing: BangumiGridLayout.verticalSpacing
        ) {
            ForEach(0..<placeholderCount, id: \.self) { _ in
                BangumiCardSkeleton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
