import Foundation

/// 超分的运行时自适应降级策略。
///
/// Anime4K 的 CNN 档在低端机 / 高温机上会把每帧 GPU 时间拖到几十毫秒，直接掉帧。
/// 这里盯三个信号，超线就往下降一档：
///
/// 1. **GPU 耗时**：滑动窗口里超预算的帧数达到阈值 → 降一档
/// 2. **热状态**：`.serious` 降一档，`.critical` 直接关掉
/// 3. **低电量模式**：直接关掉
///
/// **不做自动升档。** 降下来之后一直保持到用户手动改或者换一集 —— 自动升回去
/// 只会在临界点反复横跳，体验比一直待在低档还差。
///
/// 这是个纯状态机，不碰 Metal 也不碰时钟，所以能完整单测。
public struct SuperResolutionAdaptivePolicy: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// 单帧留给超分的 GPU 预算（毫秒）。用 `forVideoFrameRate(_:)` 按片源帧率推。
        public var budgetMilliseconds: Double
        /// 滑动窗口长度。
        public var windowSize: Int
        /// 窗口里有多少帧超预算就触发降级。
        public var overBudgetThreshold: Int

        public init(
            budgetMilliseconds: Double = 20.0,
            windowSize: Int = 90,
            overBudgetThreshold: Int = 60
        ) {
            self.budgetMilliseconds = budgetMilliseconds
            self.windowSize = max(1, windowSize)
            self.overBudgetThreshold = max(1, overBudgetThreshold)
        }

        public static let `default` = Configuration()

        /// 按片源帧率推预算：一帧的时间给超分一半，剩下一半留给解码、弹幕、
        /// UI 合成和系统本身。
        ///
        /// 之前这里写死 8ms。实测（M3）1080p 片源跑高质档中位就是 8ms，
        /// 等于一上来就踩线，手机慢两三倍必然秒降级 —— 用户点了高质档，
        /// 一秒后就被踢回快速档，根本选不上。
        ///
        /// 上下限：太低会误杀，太高就失去保护意义。
        public static func forVideoFrameRate(_ frameRate: Float?) -> Configuration {
            guard let frameRate, frameRate > 0, frameRate.isFinite else { return .default }
            let frameInterval = 1000.0 / Double(frameRate)
            return Configuration(
                budgetMilliseconds: min(25, max(8, frameInterval * 0.5)),
                windowSize: 90,
                overBudgetThreshold: 60
            )
        }
    }

    /// 策略给出的动作。
    public enum Decision: Equatable, Sendable {
        /// 维持现状。
        case hold
        /// 降一档（由调用方按 `SuperResolutionMode.degraded` 决定降到哪）。
        case downgrade(reason: Reason)
        /// 直接关掉超分。
        case disable(reason: Reason)
    }

    public enum Reason: Equatable, Sendable {
        case gpuBudget
        case thermal
        case lowPower
    }

    public private(set) var configuration: Configuration
    private var samples: [Double] = []
    private var overBudgetCount = 0

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        samples.reserveCapacity(configuration.windowSize)
    }

    /// 记一帧的 GPU 耗时。
    public mutating func record(gpuMilliseconds: Double) -> Decision {
        guard gpuMilliseconds.isFinite, gpuMilliseconds >= 0 else { return .hold }

        samples.append(gpuMilliseconds)
        if gpuMilliseconds > configuration.budgetMilliseconds {
            overBudgetCount += 1
        }

        if samples.count > configuration.windowSize {
            let dropped = samples.removeFirst()
            if dropped > configuration.budgetMilliseconds {
                overBudgetCount -= 1
            }
        }

        guard samples.count >= configuration.windowSize,
              overBudgetCount >= configuration.overBudgetThreshold
        else {
            return .hold
        }

        // 降完档之后清空窗口 —— 不然新档位的头几帧会和旧档位的慢帧混在一起，
        // 一路把档位踩到底。
        reset()
        return .downgrade(reason: .gpuBudget)
    }

    /// 记一次系统状态变化。`thermalState` 用 `ProcessInfo.ThermalState` 的 rawValue 语义。
    public mutating func record(
        thermalState: ProcessInfo.ThermalState,
        isLowPowerModeEnabled: Bool
    ) -> Decision {
        if isLowPowerModeEnabled {
            reset()
            return .disable(reason: .lowPower)
        }
        switch thermalState {
        case .critical:
            reset()
            return .disable(reason: .thermal)
        case .serious:
            reset()
            return .downgrade(reason: .thermal)
        default:
            return .hold
        }
    }

    /// 换预算。片源帧率解出来之后调用。
    public mutating func updateConfiguration(_ newValue: Configuration) {
        guard newValue != configuration else { return }
        configuration = newValue
        reset()
    }

    /// 清空采样窗口。换片源 / 换档位时调用。
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        overBudgetCount = 0
    }

    /// 当前窗口里的平均 GPU 耗时，`nil` 表示还没采到样。诊断用。
    public var averageMilliseconds: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}
