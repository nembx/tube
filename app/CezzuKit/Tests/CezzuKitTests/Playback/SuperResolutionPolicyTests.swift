import CoreGraphics
import Foundation
import Testing

@testable import CezzuKit

@Suite("超分输出尺寸策略")
struct SuperResolutionOutputSizePolicyTests {
    @Test("目标尺寸收敛到屏幕实际能画下的像素")
    func clampsToLayerPixels() {
        // 1080p 片源，iPhone 横屏 2556x1179 物理像素。
        // 老实现固定 2× 会算 3840x2160，多出来的像素屏幕根本画不出来。
        let target = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: Anime4KTextureSize(width: 1920, height: 1080),
            layerPixelSize: CGSize(width: 2556, height: 1179)
        )
        // 按宽高比塞进去，短边先满：1179/1080 ≈ 1.0917
        #expect(target.width == 2096)
        #expect(target.height == 1179)
    }

    @Test("传进来的必须是物理像素，不是点数")
    func layerSizeMustBePixelsNotPoints() {
        let source = Anime4KTextureSize(width: 1920, height: 1080)
        // iPhone 横屏全屏：约 932×430 点，3 倍屏下是 2796×1290 物理像素。
        let pixels = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: source,
            layerPixelSize: CGSize(width: 2796, height: 1290)
        )
        #expect(pixels.width > source.width, "按像素算应该还有放大空间")

        // 误把点数传进来的话倍率会算成小于 1，被 clamp 成 1:1 —— 结果就是
        // Anime4K 的放大链被它自己的 //!WHEN 门槛全部跳过，看起来「超分没生效」。
        // CAMetalLayer 的 contentsScale 默认是 1，手动加的 sublayer 不继承屏幕缩放，
        // 这个坑真踩过一次。
        let points = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: source,
            layerPixelSize: CGSize(width: 932, height: 430)
        )
        #expect(points == source)
    }

    @Test("屏幕够大时仍然吃满倍率上限")
    func respectsMaximumScale() {
        let target = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: Anime4KTextureSize(width: 960, height: 540),
            layerPixelSize: CGSize(width: 5120, height: 2880),
            maximumScale: 2.0
        )
        #expect(target == Anime4KTextureSize(width: 1920, height: 1080))
    }

    @Test("片源比屏幕还大时不缩小")
    func neverDownscalesBelowInput() {
        let target = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: Anime4KTextureSize(width: 3840, height: 2160),
            layerPixelSize: CGSize(width: 1280, height: 720)
        )
        // 缩小交给显示层的 resizeAspect，超分这一步不做降采样。
        #expect(target == Anime4KTextureSize(width: 3840, height: 2160))
    }

    @Test("layer 还没布局时退回倍率上限")
    func fallsBackWhenLayerNotLaidOut() {
        let target = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: Anime4KTextureSize(width: 640, height: 360),
            layerPixelSize: .zero,
            maximumScale: 2.0
        )
        #expect(target == Anime4KTextureSize(width: 1280, height: 720))
    }

    @Test("空输入原样返回")
    func emptyInputPassesThrough() {
        let target = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: .zero,
            layerPixelSize: CGSize(width: 100, height: 100)
        )
        #expect(target == .zero)
        #expect(SuperResolutionOutputSizePolicy.isWorthwhile(inputSize: .zero, targetSize: .zero) == false)
    }

    @Test("倍率太小时判定为不值得跑")
    func detectsNotWorthwhile() {
        let input = Anime4KTextureSize(width: 1920, height: 1080)
        #expect(
            SuperResolutionOutputSizePolicy.isWorthwhile(
                inputSize: input,
                targetSize: Anime4KTextureSize(width: 1930, height: 1085)
            ) == false
        )
        #expect(
            SuperResolutionOutputSizePolicy.isWorthwhile(
                inputSize: input,
                targetSize: Anime4KTextureSize(width: 3840, height: 2160)
            )
        )
    }
}

@Suite("超分自适应降级策略")
struct SuperResolutionAdaptivePolicyTests {
    private let configuration = SuperResolutionAdaptivePolicy.Configuration(
        budgetMilliseconds: 8,
        windowSize: 10,
        overBudgetThreshold: 6
    )

    @Test("预算按片源帧率推")
    func budgetFollowsFrameRate() {
        // 24fps 一帧 41.7ms，给超分一半 ≈ 20.8ms。
        let anime = SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(23.976)
        #expect(anime.budgetMilliseconds > 20 && anime.budgetMilliseconds <= 21)

        // 60fps 一帧 16.7ms，一半 8.3ms。
        let highRate = SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(60)
        #expect(highRate.budgetMilliseconds > 8 && highRate.budgetMilliseconds < 9)

        // 帧率越低预算越松。
        #expect(anime.budgetMilliseconds > highRate.budgetMilliseconds)
    }

    @Test("预算有上下限，极端帧率不会失控")
    func budgetIsClamped() {
        // 极低帧率不能把预算放到没有保护意义。
        let slow = SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(2)
        #expect(slow.budgetMilliseconds == 25)
        // 极高帧率也不能把预算压到误杀。
        let fast = SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(240)
        #expect(fast.budgetMilliseconds == 8)
    }

    @Test("帧率未知时退回默认预算")
    func budgetFallsBackWhenFrameRateUnknown() {
        #expect(SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(nil) == .default)
        #expect(SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(0) == .default)
        #expect(SuperResolutionAdaptivePolicy.Configuration.forVideoFrameRate(.nan) == .default)
    }

    @Test("换预算会清空已有采样")
    func updatingConfigurationResetsWindow() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        _ = policy.record(gpuMilliseconds: 12)
        #expect(policy.averageMilliseconds == 12)
        policy.updateConfiguration(.forVideoFrameRate(23.976))
        // 旧预算下的采样在新预算下没有意义，留着会误判。
        #expect(policy.averageMilliseconds == nil)
        #expect(policy.configuration.budgetMilliseconds > 20)
    }

    @Test("窗口没满不降档")
    func holdsUntilWindowFills() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        for _ in 0..<9 {
            #expect(policy.record(gpuMilliseconds: 50) == .hold)
        }
    }

    @Test("超预算的帧够多就降一档")
    func downgradesWhenOverBudget() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        var decisions: [SuperResolutionAdaptivePolicy.Decision] = []
        for _ in 0..<10 {
            decisions.append(policy.record(gpuMilliseconds: 50))
        }
        #expect(decisions.last == .downgrade(reason: .gpuBudget))
    }

    @Test("一直在预算内就不动")
    func holdsWhenWithinBudget() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        for _ in 0..<100 {
            #expect(policy.record(gpuMilliseconds: 3) == .hold)
        }
    }

    @Test("偶尔超一下不触发")
    func toleratesOccasionalSpikes() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        for index in 0..<100 {
            // 每 5 帧超一次 —— 10 帧窗口里只有 2 帧超，够不到阈值 6。
            let decision = policy.record(gpuMilliseconds: index % 5 == 0 ? 50 : 3)
            #expect(decision == .hold)
        }
    }

    @Test("降档之后清空窗口，不会连着一路降到底")
    func resetsWindowAfterDowngrade() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        for _ in 0..<10 { _ = policy.record(gpuMilliseconds: 50) }
        // 紧接着的下一帧即使还是慢的，也得重新攒满一个窗口才会再降。
        #expect(policy.record(gpuMilliseconds: 50) == .hold)
        #expect(policy.averageMilliseconds == 50)
    }

    @Test("热状态严重时降档、临界时关闭")
    func reactsToThermalState() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        #expect(
            policy.record(thermalState: .nominal, isLowPowerModeEnabled: false) == .hold
        )
        #expect(
            policy.record(thermalState: .fair, isLowPowerModeEnabled: false) == .hold
        )
        #expect(
            policy.record(thermalState: .serious, isLowPowerModeEnabled: false)
                == .downgrade(reason: .thermal)
        )
        #expect(
            policy.record(thermalState: .critical, isLowPowerModeEnabled: false)
                == .disable(reason: .thermal)
        )
    }

    @Test("低电量模式直接关闭，且优先于热状态")
    func lowPowerModeDisables() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        #expect(
            policy.record(thermalState: .nominal, isLowPowerModeEnabled: true)
                == .disable(reason: .lowPower)
        )
    }

    @Test("非法采样被忽略")
    func ignoresInvalidSamples() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        #expect(policy.record(gpuMilliseconds: .nan) == .hold)
        #expect(policy.record(gpuMilliseconds: -1) == .hold)
        #expect(policy.averageMilliseconds == nil)
    }

    @Test("reset 清空统计")
    func resetClearsSamples() {
        var policy = SuperResolutionAdaptivePolicy(configuration: configuration)
        _ = policy.record(gpuMilliseconds: 12)
        #expect(policy.averageMilliseconds == 12)
        policy.reset()
        #expect(policy.averageMilliseconds == nil)
    }
}

@Suite("超分显示链接速率策略")
struct SuperResolutionDisplayLinkPolicyTests {
    @Test("帧率未知时保持系统默认")
    func unknownFrameRateKeepsDefault() {
        #expect(SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: nil) == nil)
        #expect(SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: 0) == nil)
        #expect(SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: .nan) == nil)
    }

    @Test("按片源帧率的 2 倍收敛")
    func targetsTwiceTheVideoRate() throws {
        // 番剧最常见的 23.976fps：120Hz 屏幕上原本要空转 5 次才等到一帧新画面。
        let range = try #require(
            SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: 23.976)
        )
        #expect(range.preferred == 48)
        #expect(range.maximum == 48)
        #expect(range.minimum == 24)
    }

    @Test("高帧率片源被压在上限内")
    func clampsToMaximum() throws {
        let range = try #require(
            SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: 90)
        )
        #expect(range.preferred == SuperResolutionDisplayLinkPolicy.maximumFrameRate)
        #expect(range.minimum <= SuperResolutionDisplayLinkPolicy.maximumFrameRate)
    }

    @Test("低帧率片源不会被压到看起来卡")
    func clampsToMinimum() throws {
        let range = try #require(
            SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(videoFrameRate: 8)
        )
        #expect(range.preferred == SuperResolutionDisplayLinkPolicy.minimumFrameRate)
        #expect(range.minimum <= SuperResolutionDisplayLinkPolicy.minimumFrameRate)
    }
}
