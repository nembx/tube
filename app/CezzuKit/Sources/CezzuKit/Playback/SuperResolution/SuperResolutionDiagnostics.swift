import Foundation
import Observation

/// 超分当前到底在跑什么。
///
/// 存在的理由：超分链路上有好几处**静默降级** —— 着色器还在编译、片源是 HDR、
/// 规划失败、设备不支持，任何一处发生时画面都还是正常的，只是效果退回了 Lanczos。
/// 没有这个读数，用户切档位时看到「四个档都一样」，根本无从判断是效果不明显
/// 还是压根没生效。
public struct SuperResolutionDiagnostics: Equatable, Sendable {
    /// 退回低档的原因。
    public enum FallbackReason: Equatable, Sendable {
        /// 着色器还在后台编译，通常一两秒。
        case compiling
        /// 着色器编译失败或资源缺失，不会自己恢复。
        case compileFailed
        /// 渲染图规划失败（尺寸异常 / manifest 有问题）。
        case planFailed
        /// 片源是 PQ / HLG，Anime4K 的网络是在 SDR 上训练的，主动旁路。
        case highDynamicRange
        /// 当前设备不支持用户选的档位，已在能力探测时降级。
        case unsupported
        /// 连续多帧 GPU 超预算，自适应策略降的档。
        case gpuBudget
        /// 设备过热。
        case thermal
        /// 低电量模式。
        case lowPower

        public var displayText: String {
            switch self {
            case .compiling: return "着色器编译中"
            case .compileFailed: return "着色器不可用"
            case .planFailed: return "渲染图规划失败"
            case .highDynamicRange: return "HDR 片源"
            case .unsupported: return "设备不支持"
            case .gpuBudget: return "GPU 超预算"
            case .thermal: return "设备过热"
            case .lowPower: return "低电量模式"
            }
        }
    }

    /// 用户在菜单里选的档位。
    public var requestedMode: SuperResolutionMode
    /// 这一帧实际生效的档位。
    public var activeMode: SuperResolutionMode
    /// `activeMode` 和 `requestedMode` 不一致时的原因。
    public var fallbackReason: FallbackReason?
    public var inputSize: Anime4KTextureSize
    public var outputSize: Anime4KTextureSize
    /// Anime4K 渲染图里实际执行的 pass 数，非 Anime4K 档位是 0。
    public var passCount: Int
    /// 中间纹理峰值占用（字节）。
    public var peakBufferBytes: Int
    /// 最近一帧的 GPU 耗时。`nil` 表示还没采到。诊断日志用，不进菜单文字（见 `summary`）。
    public var lastGPUMilliseconds: Double?

    public init(
        requestedMode: SuperResolutionMode = .off,
        activeMode: SuperResolutionMode = .off,
        fallbackReason: FallbackReason? = nil,
        inputSize: Anime4KTextureSize = .zero,
        outputSize: Anime4KTextureSize = .zero,
        passCount: Int = 0,
        peakBufferBytes: Int = 0,
        lastGPUMilliseconds: Double? = nil
    ) {
        self.requestedMode = requestedMode
        self.activeMode = activeMode
        self.fallbackReason = fallbackReason
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.passCount = passCount
        self.peakBufferBytes = peakBufferBytes
        self.lastGPUMilliseconds = lastGPUMilliseconds
    }

    /// 菜单里那一行灰字。
    ///
    /// 三种形态：
    /// - 关着：`未启用`
    /// - 正常跑：`1920×1080 → 2083×1179 · 9 pass · 116MB`
    /// - 降级了：`退回效率（着色器编译中）`
    ///
    /// **刻意不放 GPU 耗时**：它每帧都在变，放进来就意味着菜单内容要跟着一直重建，
    /// 播放中拉开菜单会看到这一行不停闪。耗时走日志，那边看时间序列本来也更合适。
    public var summary: String {
        guard requestedMode != .off else { return "未启用" }

        if let fallbackReason {
            return "退回\(activeMode.displayName)（\(fallbackReason.displayText)）"
        }

        var parts: [String] = []
        if !inputSize.isEmpty, !outputSize.isEmpty {
            parts.append("\(inputSize.width)×\(inputSize.height) → \(outputSize.width)×\(outputSize.height)")
        }
        if passCount > 0 {
            parts.append("\(passCount) pass")
        }
        if peakBufferBytes > 0 {
            parts.append("\(peakBufferBytes / 1_048_576)MB")
        }
        return parts.isEmpty ? "准备中" : parts.joined(separator: " · ")
    }

    /// 菜单标题里跟在「超分辨率」后面的那一小段。关着时是 `nil`，标题就只剩「超分辨率」。
    ///
    /// 比 `summary` 短：菜单标题放不下太多字，显存那项挪走了 —— 真要看开销
    /// 日志里有。尺寸留着，它是判断「放大链到底跑没跑」最直接的依据。
    public var menuSummary: String? {
        guard requestedMode != .off else { return nil }
        if let fallbackReason {
            return "退回\(activeMode.displayName)（\(fallbackReason.displayText)）"
        }
        guard !inputSize.isEmpty, !outputSize.isEmpty else { return "准备中" }
        var text = "\(inputSize.width)×\(inputSize.height)→\(outputSize.width)×\(outputSize.height)"
        if passCount > 0 {
            text += " · \(passCount) pass"
        }
        return text
    }

    /// 是否处在「用户以为开了、其实没生效」的状态。UI 用它决定要不要标黄。
    public var isDegraded: Bool {
        requestedMode != .off && fallbackReason != nil
    }
}

/// 把流水线内部的诊断状态桥到 SwiftUI。
///
/// 和 `PlayerPictureInPictureController` 一个路子：流水线活在平台宿主视图里，
/// SwiftUI 侧拿不到它，所以用一个 `@Observable` 的桥对象传状态。
@MainActor
@Observable
public final class SuperResolutionDiagnosticsBridge {
    public private(set) var diagnostics = SuperResolutionDiagnostics()

    public init() {}

    /// 由流水线调用。相同内容不会重复赋值 —— 每帧都写会让菜单所在的视图树
    /// 一直重算。
    public func update(_ newValue: SuperResolutionDiagnostics) {
        guard newValue != diagnostics else { return }
        diagnostics = newValue
    }
}
