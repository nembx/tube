import SwiftUI

/// 音量滑块的换算。抽出来是为了脱离 SwiftUI 直接测边界条件。
enum PlayerVolumeSliderGeometry {
    /// 把落点换算成音量，超出轨道两端时夹紧。
    static func volume(atX x: CGFloat, width: CGFloat) -> Float {
        guard width > 0 else { return 0 }
        return Float(min(max(Double(x / width), 0), 1))
    }

    /// 已填段占比。脏值按静音处理。
    static func fraction(_ volume: Float) -> Double {
        guard volume.isFinite else { return 0 }
        return Double(min(max(volume, 0), 1))
    }

    /// 喇叭图标跟着音量走 —— 静音和小声得看得出区别。
    static func icon(for volume: Float) -> String {
        let level = fraction(volume)
        switch level {
        case ..<0.001: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// 顶栏左端那颗音量胶囊：一条横轨 + 右边一个喇叭。
///
/// 调的是这一路播放的音量，不动系统音量 —— 播放页上想小声一点，不该连带把别的应用也调了。
struct PlayerVolumeSlider: View {
    @Binding var volume: Float
    var height: CGFloat = 40
    var trackWidth: CGFloat = 88

    private let trackHeight: CGFloat = 6

    var body: some View {
        HStack(spacing: 10) {
            track

            Image(systemName: PlayerVolumeSliderGeometry.icon(for: volume))
                .font(.system(size: 15, weight: .semibold))
                // 跟轨道同色，否则亮白的条旁边挂一个发灰的喇叭。
                .foregroundStyle(Color.white)
                // 图标随音量换，宽度不一样 —— 定宽，免得轨道跟着抖。
                .frame(width: 24, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .glassBackground(in: Capsule())
        .accessibilityElement()
        .accessibilityLabel("音量")
        .accessibilityValue(Text("\(Int(PlayerVolumeSliderGeometry.fraction(volume) * 100))%"))
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                // 这里破例手写白色。玻璃胶囊上的 primary 试下来都偏暗，
                // 而这条要的就是参考稿里那截纯白。
                Capsule()
                    .fill(Color.white.opacity(0.32))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.white)
                    .frame(
                        width: width * PlayerVolumeSliderGeometry.fraction(volume),
                        height: trackHeight
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        volume = PlayerVolumeSliderGeometry.volume(
                            atX: value.location.x,
                            width: width
                        )
                    }
            )
        }
        .frame(width: trackWidth, height: height)
    }
}
