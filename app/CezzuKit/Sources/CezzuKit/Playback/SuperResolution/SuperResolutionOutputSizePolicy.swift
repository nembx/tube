import CoreGraphics
import Foundation

/// 决定超分要放大到多少像素。
///
/// 原来的实现固定 2×，跟屏幕多大无关 —— 1080p 片源在 iPhone 上会被放到 3840×2160，
/// 而屏幕根本画不下这么多像素，多出来的 GPU 时间和显存纯属浪费。
/// 这里按「视频在屏幕上实际占据的像素」收敛，这也正是 Anime4K 的
/// `AutoDownscalePre` 想解决的问题。
public enum SuperResolutionOutputSizePolicy {
    /// 放大倍率上限。
    ///
    /// 取 4 而不是 2：真正决定目标尺寸的是「视频在屏幕上占多少像素」，这个上限
    /// 只在片源相对屏幕特别小的时候才兜底。压到 2 会有两个坏处 ——
    /// 老片源（480p 之类）算出来的画面比屏幕上那块区域小，最后还要被 CoreAnimation
    /// 双线性拉一道，等于把刚做出来的锐度又抹掉；而且 Anime4K 自己的
    /// AutoDownscalePre 是按 OUTPUT 尺寸决定要不要走第二级放大的，OUTPUT 被压小了
    /// 它的第二级就永远不触发。Anime4K 的链本身最多做到 4×，再高也没有意义。
    public static let defaultMaximumScale: CGFloat = 4.0

    /// 低于这个倍率就认为没必要超分（片源已经比屏幕还清楚了）。
    public static let minimumUsefulScale: CGFloat = 1.05

    /// 算出超分的目标尺寸。
    ///
    /// - Parameters:
    ///   - inputSize: 解码出来的视频帧尺寸。
    ///   - layerPixelSize: 承载层的物理像素尺寸（点数 × contentsScale）。
    ///     为空时退回按 `maximumScale` 放大 —— 这发生在 layer 还没被布局的那几帧。
    ///   - maximumScale: 放大倍率上限。
    /// - Returns: 保持片源宽高比的目标尺寸，永远不会小于输入。
    public static func targetSize(
        inputSize: Anime4KTextureSize,
        layerPixelSize: CGSize,
        maximumScale: CGFloat = defaultMaximumScale
    ) -> Anime4KTextureSize {
        guard !inputSize.isEmpty else { return inputSize }
        let cappedMaximum = max(1.0, maximumScale)

        guard layerPixelSize.width >= 1, layerPixelSize.height >= 1 else {
            return scaled(inputSize, by: cappedMaximum)
        }

        // 视频以 resizeAspect 贴到 layer 上，所以它实际占的像素是「按宽高比塞进 layer」
        // 之后的那块区域，不是整个 layer。
        let widthRatio = layerPixelSize.width / CGFloat(inputSize.width)
        let heightRatio = layerPixelSize.height / CGFloat(inputSize.height)
        let fitScale = min(widthRatio, heightRatio)

        let scale = min(cappedMaximum, max(1.0, fitScale))
        return scaled(inputSize, by: scale)
    }

    /// 目标尺寸相对输入的放大倍率是否值得跑超分。
    public static func isWorthwhile(
        inputSize: Anime4KTextureSize,
        targetSize: Anime4KTextureSize
    ) -> Bool {
        guard !inputSize.isEmpty else { return false }
        return CGFloat(targetSize.width) / CGFloat(inputSize.width) >= minimumUsefulScale
    }

    private static func scaled(_ size: Anime4KTextureSize, by scale: CGFloat) -> Anime4KTextureSize {
        Anime4KTextureSize(
            width: max(1, Int((CGFloat(size.width) * scale).rounded())),
            height: max(1, Int((CGFloat(size.height) * scale).rounded()))
        )
    }
}
