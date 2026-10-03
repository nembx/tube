import Foundation
import Metal
import Testing

@testable import CezzuKit

@Suite("SuperResolutionMode")
struct SuperResolutionModeTests {
    @Test("display names cover all cases in Chinese")
    func displayNames() {
        #expect(SuperResolutionMode.off.displayName == "关闭")
        #expect(SuperResolutionMode.efficiency.displayName == "效率")
        #expect(SuperResolutionMode.quality.displayName == "质量")
    }

    @Test("requiresPipeline distinguishes off from active modes")
    func requiresPipeline() {
        #expect(SuperResolutionMode.off.requiresPipeline == false)
        #expect(SuperResolutionMode.efficiency.requiresPipeline == true)
        #expect(SuperResolutionMode.quality.requiresPipeline == true)
    }

    @Test("rawValue round-trips through Codable / RawRepresentable")
    func rawValueRoundTrip() {
        for mode in SuperResolutionMode.allCases {
            let raw = mode.rawValue
            #expect(SuperResolutionMode(rawValue: raw) == mode)
        }
    }

    @Test("off mode is always supported, even without a Metal device")
    func offIsAlwaysSupported() {
        #expect(SuperResolutionCapability.isSupported(.off, on: nil) == true)
        #expect(SuperResolutionCapability.isSupported(.efficiency, on: nil) == false)
        #expect(SuperResolutionCapability.isSupported(.quality, on: nil) == false)
    }

    @Test("quality mode is unavailable when MetalFX module is missing (e.g. simulator)")
    func qualityUnavailableWithoutMetalFXModule() {
        if !SuperResolutionCapability.isMetalFXModuleAvailable {
            #expect(SuperResolutionCapability.isSupported(.quality, on: MTLCreateSystemDefaultDevice()) == false)
            #expect(SuperResolutionCapability.resolved(.quality, on: MTLCreateSystemDefaultDevice()) != .quality)
        }
    }

    @Test("resolved degrades gracefully when device is absent")
    func resolvedNoDevice() {
        #expect(SuperResolutionCapability.resolved(.quality, on: nil) == .off)
        #expect(SuperResolutionCapability.resolved(.efficiency, on: nil) == .off)
        #expect(SuperResolutionCapability.resolved(.off, on: nil) == .off)
    }

    @Test("resolved keeps the mode when supported, otherwise downgrades")
    func resolvedWithDevice() {
        let device = MTLCreateSystemDefaultDevice()
        // 测试机不一定支持 quality；不强求具体档位，只验证降级逻辑符合 contract。
        let resolved = SuperResolutionCapability.resolved(.quality, on: device)
        #expect(SuperResolutionCapability.isSupported(resolved, on: device))

        // efficiency 在有 device 时应稳定可用
        if device != nil {
            #expect(SuperResolutionCapability.resolved(.efficiency, on: device) == .efficiency)
        }
    }

    @Test("highestAvailableMode reports the strongest mode the runtime supports")
    func highestAvailable() {
        let mode = SuperResolutionCapability.highestAvailableMode()
        let device = SuperResolutionCapability.defaultDevice
        #expect(SuperResolutionCapability.isSupported(mode, on: device))
        // 只要 device 在，至少能跑 efficiency。
        if device != nil {
            #expect(mode != .off)
        }
    }

    // MARK: - Anime4K 档位

    @Test("Anime4K 档位映射到对应预设")
    func anime4KPresets() {
        #expect(SuperResolutionMode.anime4KFast.anime4KPreset == .fast)
        #expect(SuperResolutionMode.anime4KHighQuality.anime4KPreset == .highQuality)
        #expect(SuperResolutionMode.off.anime4KPreset == nil)
        #expect(SuperResolutionMode.efficiency.anime4KPreset == nil)
        #expect(SuperResolutionMode.quality.anime4KPreset == nil)
    }

    @Test("降级链一路走到 off")
    func degradationChainTerminates() {
        #expect(SuperResolutionMode.anime4KHighQuality.degraded == .anime4KFast)
        #expect(SuperResolutionMode.anime4KFast.degraded == .efficiency)
        #expect(SuperResolutionMode.quality.degraded == .efficiency)
        #expect(SuperResolutionMode.efficiency.degraded == .off)
        #expect(SuperResolutionMode.off.degraded == .off)

        // 每个档位顺着链走都必须能到 off，不能绕圈。
        for mode in SuperResolutionMode.allCases {
            var current = mode
            var steps = 0
            while current != .off && steps <= SuperResolutionMode.allCases.count {
                current = current.degraded
                steps += 1
            }
            #expect(current == .off, "\(mode.rawValue) 的降级链没走到 off")
        }
    }

    @Test("持久化用的 rawValue 是稳定的")
    func rawValuesAreStable() {
        // 这些字符串已经写进用户的 UserDefaults 了，改动等于把大家的设置清零。
        #expect(SuperResolutionMode.off.rawValue == "off")
        #expect(SuperResolutionMode.efficiency.rawValue == "efficiency")
        #expect(SuperResolutionMode.quality.rawValue == "quality")
        #expect(SuperResolutionMode.anime4KFast.rawValue == "anime4kFast")
        #expect(SuperResolutionMode.anime4KHighQuality.rawValue == "anime4kHQ")
    }

    @Test("没有 device 时 Anime4K 档位一律不可用")
    func anime4KNeedsDevice() {
        #expect(SuperResolutionCapability.isSupported(.anime4KFast, on: nil) == false)
        #expect(SuperResolutionCapability.isSupported(.anime4KHighQuality, on: nil) == false)
        #expect(SuperResolutionCapability.resolved(.anime4KHighQuality, on: nil) == .off)
    }

    @Test("高质档的门槛不低于快速档")
    func highQualityIsNeverMorePermissive() {
        let device = MTLCreateSystemDefaultDevice()
        if SuperResolutionCapability.isSupported(.anime4KHighQuality, on: device) {
            #expect(SuperResolutionCapability.isSupported(.anime4KFast, on: device))
        }
    }
}
