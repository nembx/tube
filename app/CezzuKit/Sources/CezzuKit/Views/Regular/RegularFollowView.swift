import SwiftUI

/// 宽屏（macOS / iPad）追番页 —— 影院式头图 + 收藏宫格。
///
/// 头图沿用首页 hero 的做法：最新那部的封面放大模糊当底，标题配一行拉丁副标题，
/// 右边把最近三部叠成一摞收藏。往下滚就是整片收藏宫格。
///
/// 窄屏追番页见 `FollowView`；两者共用 `FollowLayout`，chrome 分开维护。
public struct RegularFollowView: View {
    @Bindable var followStore: FollowStore
    var onTapItem: (BangumiItem) -> Void

    public init(followStore: FollowStore, onTapItem: @escaping (BangumiItem) -> Void) {
        self.followStore = followStore
        self.onTapItem = onTapItem
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RegularShellLayout.cinemaBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header(width: geo.size.width)
                        content
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
            }
        }
        // 头图要铺到窗口最上沿从顶栏下面穿过去，否则标题栏那一条会露出外壳底色。
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }

    @ViewBuilder
    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            FollowHeaderBackdrop(
                item: followStore.items.first,
                height: FollowLayout.regularHeaderHeight
            )

            HStack(alignment: .bottom, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("追番")
                            .font(.system(size: 44, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(.white)
                        Text("MY COLLECTION")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(FollowLayout.countLabel(followStore.items.count))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                if FollowLayout.showsStack(width: width), !followStore.items.isEmpty {
                    posterStack
                }
            }
            .padding(.horizontal, RegularHomeHeroLayout.horizontalPadding)
            .padding(.bottom, 26)
        }
        .frame(height: FollowLayout.regularHeaderHeight)
    }

    /// 最近三部叠成一摞。最新那张在最前，往后依次右移、右倾、缩一档。
    @ViewBuilder
    private var posterStack: some View {
        let stack = FollowLayout.stackItems(followStore.items)
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(stack.enumerated()), id: \.offset) { index, item in
                poster(item)
                    .scaleEffect(FollowLayout.stackScale(for: index), anchor: .bottomLeading)
                    .rotationEffect(.degrees(FollowLayout.stackRotation(for: index)), anchor: .bottomLeading)
                    .offset(x: FollowLayout.stackOffsetX(for: index))
                    .zIndex(Double(stack.count - index))
            }
        }
        .padding(.trailing, FollowLayout.stackOffsetX(for: stack.count - 1))
    }

    @ViewBuilder
    private func poster(_ item: BangumiItem) -> some View {
        let height = FollowLayout.stackPosterHeight
        let shape = RoundedRectangle(
            cornerRadius: RegularHomeHeroLayout.posterCornerRadius,
            style: .continuous
        )
        Button {
            onTapItem(item)
        } label: {
            Color.clear
                .frame(
                    width: height * RegularHomeHeroLayout.posterAspectRatio,
                    height: height
                )
                .overlay {
                    RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
                        CoverColorPalette.fallback.darkened.color
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName)
    }

    @ViewBuilder
    private var content: some View {
        if followStore.items.isEmpty {
            EmptyStateView(
                systemImage: "star",
                title: "还没有追番",
                message: "在详情页点一下星标，收藏的番剧会出现在这里。"
            )
            .padding(.top, 32)
        } else {
            BangumiGrid(
                items: followStore.items,
                onTapItem: onTapItem,
                onLoadMore: { _ in }
            ) {
                EmptyView()
            }
            .padding(.horizontal, RegularHomeHeroLayout.horizontalPadding)
            .padding(.top, 12)
        }
    }
}
