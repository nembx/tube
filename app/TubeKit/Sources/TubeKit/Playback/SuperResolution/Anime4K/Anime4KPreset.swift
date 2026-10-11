import Foundation

/// 一条 Anime4K 着色器链。
///
/// 链的顺序抄的是上游 `GLSL_Instructions.md` 里的官方推荐组合，只把 CNN 规格
/// 从桌面端的 VL 换成移动端跑得动的 S / M —— 上游明确说过「每升一级规格耗时翻倍」，
/// VL 在 iPhone 上不现实。
///
/// 链里各个着色器的 `//!HOOK` 阶段会被 `Anime4KRenderPlanner` 重新分组：
/// 先跑所有 `MAIN` 阶段的 pass，再跑 `PREKERNEL` 阶段的。`Clamp_Highlights`
/// 就是靠这个机制在链头统计高光、在链尾钳制的。
public struct Anime4KPreset: Equatable, Sendable {
    /// 稳定标识，用来给编译产物做磁盘缓存的 key。
    public let id: String
    /// 按顺序引用的着色器 id（对应 manifest 里的 `id` 字段）。
    public let shaderIDs: [String]

    public init(id: String, shaderIDs: [String]) {
        self.id = id
        self.shaderIDs = shaderIDs
    }
}

extension Anime4KPreset {
    /// 快速档 = 上游 Mode C 的 S 规格。
    ///
    /// `Upscale_Denoise` 把去噪和放大合成一趟，对有压缩噪点的片源特别划算，
    /// 而且比 Mode A 少一整个 Restore 网络。
    public static let fast = Anime4KPreset(
        id: "modeC-S",
        shaderIDs: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_S",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ]
    )

    /// 高质档 = 上游 Mode A 的 M 规格。
    ///
    /// 先 Restore 修压缩伪影和模糊，再两级 x2 放大。第二级放大是在已经放大过的
    /// 分辨率上跑的，所以刻意降回 S 规格 —— 上游推荐组合也是这么配的。
    public static let highQuality = Anime4KPreset(
        id: "modeA-M",
        shaderIDs: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ]
    )

    public static let all: [Anime4KPreset] = [.fast, .highQuality]

    public static func preset(id: String) -> Anime4KPreset? {
        all.first { $0.id == id }
    }
}
