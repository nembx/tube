import SwiftUI

/// 追番页的版式参数。窄屏 `FollowView` 与宽屏 `RegularFollowView` 共用。
enum FollowLayout {
    static let compactHeaderHeight: CGFloat = 168
    static let regularHeaderHeight: CGFloat = 288
    static let compactHorizontalPadding: CGFloat = 20

    /// 窄屏头图要一路铺到状态栏顶沿，所以在版式高度之外再吃掉安全区。
    static func compactBackdropHeight(topInset: CGFloat) -> CGFloat {
        compactHeaderHeight + max(0, topInset)
    }

    /// 窄屏滚动容器的坐标系名字：头图靠它算自己被下拉了多少。
    static let compactScrollSpace = "follow.compact.scroll"

    /// 头图静止时顶在 `-topInset`，再往下就是下拉量 —— 这段要补给头图，
    /// 否则回弹时状态栏那一条会露出影院底。
    static func compactBackdropStretch(minY: CGFloat, topInset: CGFloat) -> CGFloat {
        max(0, minY + max(0, topInset))
    }

    /// 浅色模式下的页面底色。影院黑只在深色模式用。
    static let lightPageBackground = Color(white: 0.96)

    /// 浅色模式下头图蒙版用白，把模糊封面提亮成淡彩底，标题才能用深色字。
    /// 深色模式仍是压黑那一套。
    static let lightBackdropDim: Double = 0.66

    static func backdropScrim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func backdropScrimOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? backdropDim : lightBackdropDim
    }

    /// 没有收藏时头图退化成一段渐变，起点也得跟着明暗走，
    /// 否则浅色模式下会在页面顶上糊一块深紫。
    static func emptyBackdropTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? CoverColorPalette.fallback.darkened.color : Color(white: 0.86)
    }

    /// 窄屏追番页的页面底色 —— 跟随系统明暗。
    /// 头图底部的收口渐变要收到同一个颜色上，否则接缝处会有硬边。
    static func pageBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? RegularShellLayout.cinemaBackground : lightPageBackground
    }

    /// 头图 = 最新那部的封面放大模糊，和首页 hero 是同一套做法。
    static let backdropBlurRadius: CGFloat = 30
    static let backdropOverscan: CGFloat = 1.25
    static let backdropDim: Double = 0.46

    /// 收藏堆最多摆几张封面。
    static let stackLimit: Int = 3
    static let stackPosterHeight: CGFloat = 172
    /// 每往后一张：右移、右倾、缩一档。
    static let stackStepX: CGFloat = 36
    static let stackStepRotation: Double = 5
    static let stackStepScale: CGFloat = 0.07
    /// 窗口窄于这个宽度就不摆收藏堆，把宽度全留给标题。
    static let stackMinimumWidth: CGFloat = 820

    /// 收藏堆里从上到下的那几部（0 = 最新，摆最前面）。
    static func stackItems(_ items: [BangumiItem]) -> [BangumiItem] {
        Array(items.prefix(stackLimit))
    }

    static func stackOffsetX(for index: Int) -> CGFloat {
        CGFloat(index) * stackStepX
    }

    static func stackRotation(for index: Int) -> Double {
        Double(index) * stackStepRotation
    }

    static func stackScale(for index: Int) -> CGFloat {
        max(0.5, 1 - CGFloat(index) * stackStepScale)
    }

    static func showsStack(width: CGFloat) -> Bool {
        width >= stackMinimumWidth
    }

    static func countLabel(_ count: Int) -> String {
        "已收藏 \(count) 部"
    }
}

/// 追番页头图底衬：最新那部的封面放大模糊 + 蒙版 + 底部收口到页面底色。
struct FollowHeaderBackdrop: View {
    let item: BangumiItem?
    let height: CGFloat
    /// 底部收口的目标色 —— 必须和页面底色一致。宽屏壳恒定影院黑，窄屏跟随系统。
    var baseColor: Color = RegularShellLayout.cinemaBackground
    /// 蒙版按哪套明暗刷。宽屏壳恒定深色，窄屏跟随系统。
    var scheme: ColorScheme = .dark

    var body: some View {
        ZStack {
            if let item {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        RemoteImage(url: HomeHeroBannerLayout.coverURL(for: item)) {
                            CoverColorPalette.fallback.darkened.color
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: FollowLayout.backdropBlurRadius, opaque: true)
                        .scaleEffect(FollowLayout.backdropOverscan)
                    }
                    .clipped()
                    .overlay {
                        FollowLayout.backdropScrim(scheme)
                            .opacity(FollowLayout.backdropScrimOpacity(scheme))
                    }
            } else {
                LinearGradient(
                    colors: [
                        FollowLayout.emptyBackdropTop(scheme),
                        baseColor,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: baseColor.opacity(0.85), location: 0.82),
                    .init(color: baseColor, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// 窄屏（iPhone）追番页 —— 顶部一段封面头图，下面是收藏宫格。
///
/// 页面底色跟随系统明暗（首页那套强制影院深色是为了压住整屏 banner，这里没有）：
/// 深色模式下头图压黑配白字，浅色模式下头图提白配深字，顶区和正文才连得上。
/// 页面标题由头图自己承担，所以导航栏留空。宽屏追番页见 `RegularFollowView`。
public struct FollowView: View {
    @Bindable var followStore: FollowStore
    var onTapItem: (BangumiItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BangumiAuthStore.self) private var auth
    @Environment(BangumiCollectionStore.self) private var collections
    /// 登录后按 bgm 状态筛选；nil 是全部。
    @State private var selectedType: BangumiCollectionType? = nil

    public init(followStore: FollowStore, onTapItem: @escaping (BangumiItem) -> Void) {
        self.followStore = followStore
        self.onTapItem = onTapItem
    }

    public var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top

            ZStack {
                FollowLayout.pageBackground(colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header(topInset: topInset)
                        content
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(.named(FollowLayout.compactScrollSpace))
            }
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }

    @ViewBuilder
    private func header(topInset: CGFloat) -> some View {
        let height = FollowLayout.compactBackdropHeight(topInset: topInset)

        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let stretch = FollowLayout.compactBackdropStretch(
                    minY: proxy.frame(in: .named(FollowLayout.compactScrollSpace)).minY,
                    topInset: topInset
                )

                FollowHeaderBackdrop(
                    item: followStore.items.first,
                    height: height + stretch,
                    baseColor: FollowLayout.pageBackground(colorScheme),
                    scheme: colorScheme
                )
                .offset(y: -stretch)
            }
            .frame(height: height)

            VStack(alignment: .leading, spacing: 6) {
                Text("追番")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                Text(FollowLayout.countLabel(followStore.items.count))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, FollowLayout.compactHorizontalPadding)
            .padding(.bottom, 18)
        }
        .frame(height: height)
        // 头图向上顶进状态栏，后面的宫格不跟着位移。
        .padding(.top, -topInset)
    }

    private var visibleItems: [BangumiItem] {
        guard auth.isLoggedIn else { return followStore.items }
        return collections.filter(followStore.items, by: selectedType)
    }

    @ViewBuilder
    private var content: some View {
        if followStore.items.isEmpty {
            EmptyStateView(
                systemImage: "star",
                title: "还没有追番",
                message: auth.isLoggedIn
                    ? "在详情页标记想看 / 在看，或在设置里同步 Bangumi 收藏。"
                    : "在详情页点一下星标，收藏的番剧会出现在这里。"
            )
            .padding(.top, 24)
        } else {
            if auth.isLoggedIn {
                BangumiCollectionFilterBar(
                    selected: $selectedType,
                    items: followStore.items,
                    scheme: colorScheme
                )
                .padding(.horizontal, FollowLayout.compactHorizontalPadding)
                .padding(.top, 10)
            }
            if visibleItems.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "这一类还没有番剧",
                    message: "换个状态看看。"
                )
                .padding(.top, 24)
            } else {
                BangumiGrid(
                    items: visibleItems,
                    onTapItem: onTapItem,
                    onLoadMore: { _ in }
                ) {
                    EmptyView()
                }
                .padding(.horizontal, FollowLayout.compactHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
    }
}
