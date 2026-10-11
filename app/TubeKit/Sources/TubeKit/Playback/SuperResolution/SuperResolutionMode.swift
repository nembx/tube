import Foundation
import Metal
#if canImport(MetalFX)
import MetalFX
#endif

/// 播放器实时超分辨率档位。
///
/// 五档对应四条渲染路径（细节见 `VideoSuperResolutionPipeline`）：
/// - `.off`：完全旁路，沿用 `AVPlayerLayer`，零额外开销。
/// - `.efficiency`：基于 Core Image / Metal 的低成本上采样（Lanczos）。
/// - `.quality`：MetalFX `MTLFXSpatialScaler`，通用空间超分。
/// - `.anime4KFast` / `.anime4KHighQuality`：Anime4K CNN，专门针对动画的细线条、
///   平坦色块和压缩振铃训练，同等开销下对番剧的效果明显好于通用超分。
///
/// 注意：某档不可用时（模拟器没有 MetalFX、老 GPU 跑不动 Anime4K 高质档），
/// `SuperResolutionCapability.resolved(_:on:)` 会顺着 `degraded` 链往下降。
public enum SuperResolutionMode: String, CaseIterable, Sendable, Codable {
    case off
    case efficiency
    case quality
    case anime4KFast = "anime4kFast"
    case anime4KHighQuality = "anime4kHQ"

    public var displayName: String {
        switch self {
        case .off: return "关闭"
        case .efficiency: return "效率"
        case .quality: return "质量"
        case .anime4KFast: return "Anime4K 快速"
        case .anime4KHighQuality: return "Anime4K 高质"
        }
    }

    public var summary: String {
        switch self {
        case .off:
            return "不做画面增强，最省电。"
        case .efficiency:
            return "轻量上采样，适合低端设备。"
        case .quality:
            return "MetalFX 高质量上采样，通用场景画质最佳，GPU 占用高。"
        case .anime4KFast:
            return "Anime4K 去噪 + 放大，压制压缩噪点，GPU 占用中等。"
        case .anime4KHighQuality:
            return "Anime4K 修复 + 两级放大，线条最锐利，GPU 与显存占用最高。"
        }
    }

    /// 该模式是否需要走 SR 渲染流水线（即不是 `.off`）。
    public var requiresPipeline: Bool { self != .off }

    /// 该模式对应的 Anime4K 预设。非 Anime4K 档位返回 `nil`。
    public var anime4KPreset: Anime4KPreset? {
        switch self {
        case .anime4KFast: return .fast
        case .anime4KHighQuality: return .highQuality
        case .off, .efficiency, .quality: return nil
        }
    }

    /// 跑不动时往下降一档。自适应降级和能力探测都顺着这条链走。
    public var degraded: SuperResolutionMode {
        switch self {
        case .anime4KHighQuality: return .anime4KFast
        case .anime4KFast: return .efficiency
        case .quality: return .efficiency
        case .efficiency: return .off
        case .off: return .off
        }
    }
}

/// 设备能力探测：判断当前 GPU 是否能跑指定档位。
public enum SuperResolutionCapability {
    /// 系统提供的默认 Metal 设备。`nil` 表示当前进程没有可用 GPU（极少数 CI / 模拟器场景）。
    public static var defaultDevice: MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    /// 进程是否能 import / link MetalFX（模拟器 SDK 通常没有这个模块）。
    public static var isMetalFXModuleAvailable: Bool {
        #if canImport(MetalFX)
        true
        #else
        false
        #endif
    }

    /// 给定 device 是否支持指定模式。
    public static func isSupported(_ mode: SuperResolutionMode, on device: MTLDevice?) -> Bool {
        switch mode {
        case .off:
            return true
        case .efficiency:
            return device != nil
        case .quality:
            return supportsMetalFXSpatial(on: device)
        case .anime4KFast:
            return device != nil
        case .anime4KHighQuality:
            return supportsAnime4KHighQuality(on: device)
        }
    }

    /// 当前进程默认 device 上的最高可用档位。
    public static func highestAvailableMode() -> SuperResolutionMode {
        let device = defaultDevice
        for mode in [
            SuperResolutionMode.anime4KHighQuality,
            .anime4KFast,
            .quality,
            .efficiency,
        ] where isSupported(mode, on: device) {
            return mode
        }
        return .off
    }

    /// 给定 mode 不可用时，顺着 `degraded` 链找最接近的可用档位。
    public static func resolved(_ mode: SuperResolutionMode, on device: MTLDevice?) -> SuperResolutionMode {
        var candidate = mode
        // 链长有限（最长 off <- efficiency <- fast <- HQ），加个计数只是防御死循环。
        for _ in 0...SuperResolutionMode.allCases.count {
            if isSupported(candidate, on: device) { return candidate }
            candidate = candidate.degraded
        }
        return .off
    }

    private static func supportsMetalFXSpatial(on device: MTLDevice?) -> Bool {
        #if canImport(MetalFX)
        guard let device else { return false }
        return MTLFXSpatialScalerDescriptor.supportsDevice(device)
        #else
        return false
        #endif
    }

    /// Anime4K 高质档跑的是 M 规格 CNN：Restore 的最后一层要同时读 7 张全分辨率
    /// 中间纹理（1080p 下约 116MB 显存），每帧还要 encode 十几个 compute pass。
    /// A14（apple7）以下的移动 GPU 扛不住，会被自适应策略立刻降级 ——
    /// 与其让用户先卡一下再降，不如一开始就不给选。
    private static func supportsAnime4KHighQuality(on device: MTLDevice?) -> Bool {
        guard let device else { return false }
        return device.supportsFamily(.apple7) || device.supportsFamily(.mac2)
    }
}
