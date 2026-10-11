import SwiftUI

/// 进度条的几何换算。抽出来是为了脱离 SwiftUI 直接测边界条件。
enum PlayerProgressBarGeometry {
    /// 播放进度占比，`duration` 无效时按 0 处理。
    static func fraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// 把拖拽落点换算回时间，超出轨道两端时夹紧。
    static func position(atX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration.isFinite, duration > 0 else { return 0 }
        let ratio = min(max(Double(x / width), 0), 1)
        return ratio * duration
    }

    /// 已播段末端的 x —— 两端各留半个圆头宽，避免圆头被切掉。
    static func thumbCenterX(fraction: Double, width: CGFloat, thumbWidth: CGFloat) -> CGFloat {
        let half = thumbWidth / 2
        guard width > thumbWidth else { return width / 2 }
        return half + CGFloat(min(max(fraction, 0), 1)) * (width - thumbWidth)
    }

    /// 跑马灯高亮段的宽度：轨道的三分之一，短轨道上也不至于缩成一个点。
    static func marqueeSegmentWidth(trackWidth: CGFloat) -> CGFloat {
        max(trackWidth / 3, 40)
    }

    /// 跑马灯高亮段左边缘的 x。`phase` 走 0...1 一个来回，段从轨道左外侧滑到右外侧。
    static func marqueeOffsetX(phase: Double, trackWidth: CGFloat, segmentWidth: CGFloat) -> CGFloat {
        let clamped = min(max(phase, 0), 1)
        return CGFloat(clamped) * (trackWidth + segmentWidth) - segmentWidth
    }

    /// 一圈跑马灯的时长。
    static let marqueePeriod: Double = 1.5

    /// 当前时刻在这一圈里的进度。用挂钟算而不是靠 `withAnimation` 记状态，
    /// 免得视图被重建时动画断掉、卡在半路。
    static func marqueePhase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: marqueePeriod)
        return elapsed / marqueePeriod
    }

    /// 预览窗跟着把手走，但拖到两端时要夹住，不能飘出轨道之外。
    static func previewCenterX(
        thumbCenterX: CGFloat,
        width: CGFloat,
        previewWidth: CGFloat
    ) -> CGFloat {
        let half = previewWidth / 2
        guard width > previewWidth else { return width / 2 }
        return min(max(thumbCenterX, half), width - half)
    }
}

/// 播放进度条：已播 / 已缓冲 / 未加载三段胶囊，没有把手。
///
/// 不用原生 `Slider` 是因为它一定会画一个圆点把手，而这里已播那一段自己就是指示物 ——
/// 再摆一个把手只会在细轨道上多出一个突起。
struct PlayerProgressBar<Preview: View>: View {
    @Binding var position: TimeInterval
    let duration: TimeInterval
    let bufferedTime: TimeInterval?
    /// 语义对齐 `Slider(onEditingChanged:)`：拖拽开始传 true，结束传 false。
    let onEditingChanged: (Bool) -> Void
    /// 还没拿到时长时走跑马灯：画一段来回滑的高亮，并且不接受拖拽。
    var isIndeterminate: Bool = false
    /// 拖拽期间浮在把手正上方的预览窗。宽度由 `previewWidth` 固定，方便夹边。
    @ViewBuilder let preview: () -> Preview

    @State private var isDragging = false

    private let previewWidth: CGFloat = 168
    /// 预览窗底边与轨道之间留出的抬升量（含预览自身高度）。
    private let previewLift: CGFloat = 84
    private let idleTrackHeight: CGFloat = 6
    private let activeTrackHeight: CGFloat = 10
    /// 轨道上下留出的感应区。轨道最厚也只有 10pt，照这个高度接手势按不中。
    private let touchPadding: CGFloat = 12

    private var trackHeight: CGFloat {
        isDragging ? activeTrackHeight : idleTrackHeight
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let playedFraction = PlayerProgressBarGeometry.fraction(
                position: position,
                duration: duration
            )
            let bufferedFraction = PlayerProgressBarGeometry.fraction(
                position: bufferedTime ?? 0,
                duration: duration
            )

            ZStack(alignment: .leading) {
                if isIndeterminate {
                    marqueeTrack(width: width)
                } else {
                    Capsule()
                        .fill(.primary.opacity(0.28))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(.primary.opacity(0.45))
                        .frame(width: width * bufferedFraction, height: trackHeight)

                    // 显式纯白，不走 `.primary`：控制层压在玻璃胶囊上，层级样式会被
                    // vibrancy 混掉一截，已播那段看着就发灰。
                    Capsule()
                        .fill(.white)
                        .frame(width: width * playedFraction, height: trackHeight)
                }

                if isDragging, !isIndeterminate {
                    // 预览窗跟着已播那一段的末端走 —— 没有把手，那一端就是当前位置。
                    let headX = PlayerProgressBarGeometry.thumbCenterX(
                        fraction: playedFraction,
                        width: width,
                        thumbWidth: 4
                    )

                    preview()
                        .frame(width: previewWidth)
                        .position(
                            x: PlayerProgressBarGeometry.previewCenterX(
                                thumbCenterX: headX,
                                width: width,
                                previewWidth: previewWidth
                            ),
                            y: proxy.size.height / 2
                        )
                        // 浮到轨道上方，不参与布局也不吃手势。
                        .offset(y: -previewLift)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            // 跑马灯期间没有时长可跳，整条不接手势。
            .allowsHitTesting(!isIndeterminate)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        position = PlayerProgressBarGeometry.position(
                            atX: value.location.x,
                            width: width,
                            duration: duration
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        // 固定外框高度，拖拽时轨道涨高不会顶动两边的时间与按钮。
        .frame(height: activeTrackHeight + touchPadding)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue(
            isIndeterminate
                ? Text("正在载入")
                : Text("\(Int(position)) 秒，共 \(Int(duration)) 秒")
        )
    }

    /// 跑马灯轨道：底轨照旧，上面滑一段渐隐的高亮。
    @ViewBuilder
    private func marqueeTrack(width: CGFloat) -> some View {
        let segment = PlayerProgressBarGeometry.marqueeSegmentWidth(trackWidth: width)
        ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(0.28))
                .frame(height: trackHeight)

            TimelineView(.animation) { context in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .primary.opacity(0),
                                .primary.opacity(0.75),
                                .primary.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: segment, height: trackHeight)
                    .offset(
                        x: PlayerProgressBarGeometry.marqueeOffsetX(
                            phase: PlayerProgressBarGeometry.marqueePhase(at: context.date),
                            trackWidth: width,
                            segmentWidth: segment
                        )
                    )
            }
        }
        .frame(width: width, height: trackHeight, alignment: .leading)
        // 按轨道自己的形状裁，不是按外框矩形 —— 否则滑过两端的高亮会被切成直角，
        // 整条看上去就从胶囊变成了方条。
        .clipShape(Capsule())
    }
}
