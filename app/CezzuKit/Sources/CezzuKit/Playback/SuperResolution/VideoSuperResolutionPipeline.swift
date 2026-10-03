import AVFoundation
import CoreVideo
import Foundation
import Metal
import QuartzCore
import os

/// 实时超分辨率渲染流水线。
///
/// 工作方式：
/// 1. 给当前 `AVPlayerItem` 挂一个 `AVPlayerItemVideoOutput`，按显示时钟节拍取帧。
/// 2. 把每帧 `CVPixelBuffer` 转 `MTLTexture`，喂给 `VideoSuperResolutionScaler`。
/// 3. 把放大后的纹理 blit 到 `CAMetalLayer` 的 drawable 上展示。
///
/// 当前帧的 `AVPlayerItem` 切换、模式切换、播放器停止时，pipeline 会自动重置内部状态。
///
/// **重要约束**：pipeline 自身不持有 `CADisplayLink` / `CVDisplayLink`，
/// 平台层（`PlayerSurface` 的 UIView / NSView 桥）负责按显示节拍调用 `drawNextFrame()`。
/// 这样 pipeline 本身能保持平台中立，符合 §3.1（CezzuKit 内不写平台分叉）。
/// 装通知观察者的小盒子。
///
/// `VideoSuperResolutionPipeline` 是 `@MainActor` 的，而 `deinit` 是 nonisolated 的，
/// 没法在里面读它的可变属性。把 token 放进一个自己负责注销的对象里，
/// pipeline 释放时盒子跟着释放，通知也就摘干净了。
private final class NotificationObserverBox: @unchecked Sendable {
    var tokens: [any NSObjectProtocol] = []

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
public final class VideoSuperResolutionPipeline {
    public let metalLayer: CAMetalLayer
    public let device: any MTLDevice

    private let commandQueue: any MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private let logger = Logger(subsystem: "com.bent2685.cezzu", category: "SuperResolution")

    private weak var currentItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?

    /// 用户在菜单里选的档位。自适应降级**不会**改它 —— 用户的选择就该留在那儿。
    private var mode: SuperResolutionMode = .off
    /// 这一路播放实际在跑的档位。自适应策略只动它。
    ///
    /// 早先的实现是把降级结果写回设置项，结果用户点「高质」一秒后就被踢回
    /// 「快速」，菜单里的勾也跟着跳走 —— 看起来就像这个档位根本选不上。
    /// 现在勾留在用户选的那一档，实际跑的是哪档由菜单里的读数说明。
    private var effectiveMode: SuperResolutionMode = .off
    /// 降到当前档位的原因，`nil` 表示没降过。
    private var adaptiveFallbackReason: SuperResolutionDiagnostics.FallbackReason?
    private var scaler: (any VideoSuperResolutionScaler)?
    /// Anime4K 还在后台编译、或者这一帧规划失败时顶上的备胎。
    /// 有它才不会出现「开了超分反而黑屏 / 卡住上一帧」。
    private var fallbackScaler: (any VideoSuperResolutionScaler)?

    private lazy var anime4KLoader = Anime4KLibraryLoader(device: device)

    private var inputSize = Anime4KTextureSize.zero
    private var outputSize = Anime4KTextureSize.zero
    private var maximumScale: CGFloat = SuperResolutionOutputSizePolicy.defaultMaximumScale
    private var configuredColorSpace: CGColorSpace?
    /// 片源是 PQ / HLG 时置位。Anime4K 的 CNN 是在 SDR 上训练的，
    /// 直接喂 HDR 会把高光推爆，所以这种片源一律走备胎。
    private var isHighDynamicRange = false

    private var adaptivePolicy = SuperResolutionAdaptivePolicy()
    /// 片源的标称帧率，取到之后平台层可以据此收敛显示链接的刷新率。
    public private(set) var nominalVideoFrameRate: Float?
    /// 诊断读数变化时回调。平台层接到 UI 上，让用户看得见「到底在跑什么」。
    public var onDiagnosticsChange: ((SuperResolutionDiagnostics) -> Void)?
    private var lastPublishedDiagnostics: SuperResolutionDiagnostics?
    private var lastGPUMilliseconds: Double?
    /// 这一帧走的是主 scaler 还是备胎。
    private var didUseFallbackScaler = false
    private let systemStateObservers = NotificationObserverBox()

    /// 输出超分倍率上限。真正的目标尺寸由 `SuperResolutionOutputSizePolicy`
    /// 结合承载层的物理像素算出来 —— 固定 2× 会在手机上算一堆屏幕根本画不下的像素。
    public static let defaultOutputScale: CGFloat = SuperResolutionOutputSizePolicy.defaultMaximumScale

    public init?(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.contentsGravity = .resizeAspect
        layer.isOpaque = true
        self.metalLayer = layer

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { return nil }
        self.textureCache = cache

        observeSystemState()
    }

    // MARK: - public API

    /// 切到新的播放 item。pipeline 会重新挂 video output，重置 scaler。
    /// 如果传入和当前相同的 item，是 no-op（避免被 SwiftUI 高频 update 反复 remove/add）。
    public func attach(to item: AVPlayerItem?) {
        if item === currentItem, videoOutput != nil || item == nil {
            return
        }
        if let oldOutput = videoOutput, let oldItem = currentItem {
            oldItem.remove(oldOutput)
        }
        videoOutput = nil
        resetFrameState()
        currentItem = item
        // 换一集重新给用户选的档位一次机会 —— 上一集降下来多半是那一集的
        // 分辨率或者当时的机器状态导致的。
        effectiveMode = mode
        adaptiveFallbackReason = nil
        adaptivePolicy.reset()
        nominalVideoFrameRate = nil

        guard let item else { return }
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        output.suppressesPlayerRendering = false
        item.add(output)
        videoOutput = output
    }

    /// 切换超分模式。`.off` 时清空 scaler，pipeline 不会再画任何帧。
    public func setMode(_ newMode: SuperResolutionMode) {
        guard newMode != mode else { return }
        mode = newMode
        effectiveMode = newMode
        adaptiveFallbackReason = nil
        resetFrameState()
        adaptivePolicy.reset()
        lastGPUMilliseconds = nil
        didUseFallbackScaler = false
        if let preset = newMode.anime4KPreset {
            // 提前起编译，别等到第一帧才开始。
            anime4KLoader.prewarm(preset)
        }
        publishDiagnosticsIfNeeded()
    }

    /// 调整输出超分倍率上限（默认 2×）。后续帧会重建 scaler。
    public func setOutputScale(_ scale: CGFloat) {
        let clamped = max(1.0, min(scale, 4.0))
        guard clamped != maximumScale else { return }
        maximumScale = clamped
        resetFrameState()
    }

    /// 由平台显示时钟驱动：尝试取一帧、超分、贴到 layer。
    public func drawNextFrame() {
        guard mode.requiresPipeline else { return }
        guard let videoOutput, let textureCache else { return }

        // layer 还没被布局 / 不可见 / 没附着到 window 时直接跳帧 ——
        // 否则 nextDrawable() 会阻塞主线程，触发"彩虹球"。
        let layerSize = metalLayer.bounds.size
        if layerSize.width < 1 || layerSize.height < 1 {
            return
        }

        let now = CACurrentMediaTime()
        let hostTime = videoOutput.itemTime(forHostTime: now)
        guard hostTime.isValid, !hostTime.isIndefinite else { return }
        guard videoOutput.hasNewPixelBuffer(forItemTime: hostTime) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostTime,
            itemTimeForDisplay: nil
        ) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        configureColorSpaceIfNeeded(from: pixelBuffer)
        updateNominalFrameRateIfNeeded()

        let layerPixelSize = CGSize(
            width: layerSize.width * metalLayer.contentsScale,
            height: layerSize.height * metalLayer.contentsScale
        )
        let newInputSize = Anime4KTextureSize(width: width, height: height)
        let newOutputSize = SuperResolutionOutputSizePolicy.targetSize(
            inputSize: newInputSize,
            layerPixelSize: layerPixelSize,
            maximumScale: maximumScale
        )

        if newInputSize != inputSize || newOutputSize != outputSize || scaler == nil {
            inputSize = newInputSize
            outputSize = newOutputSize
            rebuildScalers()
            metalLayer.drawableSize = CGSize(width: outputSize.width, height: outputSize.height)
        }

        guard let inputTexture = makeTexture(from: pixelBuffer, cache: textureCache) else { return }

        // CAMetalLayer 的 drawable.texture 默认只有 `.renderTarget` 这一种 usage，
        // MetalFX 要求输出纹理含 `.shaderWrite`，直接写会触发 assert。
        // 统一走"中间纹理 → blit 到 drawable"路径。
        guard let intermediate = makeIntermediateTexture(
            width: outputSize.width,
            height: outputSize.height
        ) else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if !encode(input: inputTexture, output: intermediate, commandBuffer: commandBuffer) {
            commandBuffer.commit()
            return
        }

        guard let drawable = metalLayer.nextDrawable() else {
            commandBuffer.commit()
            return
        }
        let outputTexture = drawable.texture
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            let copyWidth = min(intermediate.width, outputTexture.width)
            let copyHeight = min(intermediate.height, outputTexture.height)
            blit.copy(
                from: intermediate,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
                to: outputTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
        }

        installGPUTimingHandler(on: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()

        publishDiagnosticsIfNeeded()
    }

    /// 释放 video output 引用。`PlaybackCoordinator` / `PlayerSurface` 销毁时调用。
    public func detach() {
        if let output = videoOutput, let item = currentItem {
            item.remove(output)
        }
        videoOutput = nil
        currentItem = nil
        resetFrameState()
    }

    // MARK: - 编码

    /// 先走主 scaler，失败（Anime4K 还在编译 / 规划失败）就退回备胎。
    private func encode(
        input: any MTLTexture,
        output: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) -> Bool {
        if let scaler, scaler.encode(input: input, output: output, commandBuffer: commandBuffer) {
            didUseFallbackScaler = false
            return true
        }
        if let fallbackScaler {
            didUseFallbackScaler = true
            return fallbackScaler.encode(input: input, output: output, commandBuffer: commandBuffer)
        }
        return false
    }

    private func rebuildScalers() {
        let effectiveMode = isHighDynamicRange && self.effectiveMode.anime4KPreset != nil
            ? .quality
            : self.effectiveMode
        scaler = VideoSuperResolutionScalerFactory.make(
            mode: effectiveMode,
            device: device,
            inputWidth: inputSize.width,
            inputHeight: inputSize.height,
            outputWidth: outputSize.width,
            outputHeight: outputSize.height,
            anime4KLoader: anime4KLoader
        )
        // Anime4K 是异步编译的，编好之前得有东西顶着；其他档位是同步就绪的，
        // 不需要备胎。
        fallbackScaler = effectiveMode.anime4KPreset == nil
            ? nil
            : LanczosVideoSuperResolutionScaler(device: device)
    }

    private func resetFrameState() {
        scaler = nil
        fallbackScaler = nil
        inputSize = .zero
        outputSize = .zero
    }

    // MARK: - 自适应降级

    private func installGPUTimingHandler(on commandBuffer: any MTLCommandBuffer) {
        guard effectiveMode.anime4KPreset != nil else { return }
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            Task { @MainActor in
                self?.recordGPUSample(milliseconds)
            }
        }
    }

    private func recordGPUSample(_ milliseconds: Double) {
        lastGPUMilliseconds = milliseconds
        apply(adaptivePolicy.record(gpuMilliseconds: milliseconds))
    }

    private func observeSystemState() {
        let center = NotificationCenter.default
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.recordSystemState()
            }
        }
        systemStateObservers.tokens = [
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil,
                using: handler
            ),
            center.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: nil,
                using: handler
            ),
        ]
    }

    private func recordSystemState() {
        guard effectiveMode.anime4KPreset != nil else { return }
        apply(
            adaptivePolicy.record(
                thermalState: ProcessInfo.processInfo.thermalState,
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        )
    }

    private func apply(_ decision: SuperResolutionAdaptivePolicy.Decision) {
        let target: SuperResolutionMode
        let cause: SuperResolutionAdaptivePolicy.Reason
        switch decision {
        case .hold:
            return
        case .downgrade(let reason):
            target = effectiveMode.degraded
            cause = reason
        case .disable(let reason):
            target = .off
            cause = reason
        }
        guard target != effectiveMode else { return }

        logger.notice("超分自动降档 \(self.effectiveMode.rawValue, privacy: .public) -> \(target.rawValue, privacy: .public) 原因=\(String(describing: cause), privacy: .public) 窗口均值=\(self.adaptivePolicy.averageMilliseconds ?? -1, privacy: .public)ms 预算=\(self.adaptivePolicy.configuration.budgetMilliseconds, privacy: .public)ms")

        effectiveMode = target
        adaptiveFallbackReason = Self.fallbackReason(for: cause)
        // 只重建 scaler，不动用户选的档位。
        resetFrameState()
        publishDiagnosticsIfNeeded()
    }

    private static func fallbackReason(
        for reason: SuperResolutionAdaptivePolicy.Reason
    ) -> SuperResolutionDiagnostics.FallbackReason {
        switch reason {
        case .gpuBudget: return .gpuBudget
        case .thermal: return .thermal
        case .lowPower: return .lowPower
        }
    }

    // MARK: - 诊断

    /// 组装当前的诊断读数。
    private func makeDiagnostics() -> SuperResolutionDiagnostics {
        var activeMode = effectiveMode
        var reason: SuperResolutionDiagnostics.FallbackReason? = adaptiveFallbackReason

        if isHighDynamicRange, effectiveMode.anime4KPreset != nil {
            activeMode = .quality
            reason = .highDynamicRange
        } else if didUseFallbackScaler, let preset = effectiveMode.anime4KPreset {
            activeMode = .efficiency
            // 备胎顶上的原因有两种：着色器没就绪，或者渲染图规划挂了。
            if let anime4KScaler = scaler as? Anime4KVideoSuperResolutionScaler,
               anime4KScaler.hasPlanningFailed {
                reason = .planFailed
            } else {
                reason = anime4KLoader.pendingReason(for: preset) ?? .planFailed
            }
        }

        let anime4KScaler = scaler as? Anime4KVideoSuperResolutionScaler
        return SuperResolutionDiagnostics(
            requestedMode: mode,
            activeMode: activeMode,
            fallbackReason: reason,
            inputSize: inputSize,
            outputSize: outputSize,
            passCount: reason == nil ? (anime4KScaler?.passCount ?? 0) : 0,
            peakBufferBytes: reason == nil ? (anime4KScaler?.peakBufferBytes ?? 0) : 0,
            lastGPUMilliseconds: reason == nil ? lastGPUMilliseconds : nil
        )
    }

    /// 发布诊断读数。
    ///
    /// **只在状态真的变了才发**（档位、尺寸、pass 数、降级原因），不按时间心跳。
    /// 早先的版本按 2Hz 发，把每帧都在变的 GPU 耗时也带上了 —— 结果播放中拉开
    /// 超分菜单，那一行读数每 0.5 秒重建一次，肉眼看就是一闪一闪的。
    /// GPU 耗时现在只进日志。
    private func publishDiagnosticsIfNeeded() {
        guard onDiagnosticsChange != nil else { return }
        let current = makeDiagnostics()

        let isStateChange = lastPublishedDiagnostics.map {
            $0.requestedMode != current.requestedMode
                || $0.activeMode != current.activeMode
                || $0.fallbackReason != current.fallbackReason
                || $0.inputSize != current.inputSize
                || $0.outputSize != current.outputSize
                || $0.passCount != current.passCount
        } ?? true
        guard isStateChange else { return }

        lastPublishedDiagnostics = current
        onDiagnosticsChange?(current)
    }

    // MARK: - 色彩与帧率

    /// 把片源的色彩空间贴到输出层上。
    ///
    /// 原来这里什么都不设，`CAMetalLayer` 就按设备默认色彩空间解释像素，
    /// BT.601 / BT.709 / BT.2020 的片源颜色会互相串。
    private func configureColorSpaceIfNeeded(from pixelBuffer: CVPixelBuffer) {
        guard configuredColorSpace == nil else { return }

        let attachments = CVBufferCopyAttachments(pixelBuffer, .shouldPropagate)
        if let attachments,
           let colorSpace = CVImageBufferCreateColorSpaceFromAttachments(attachments)?
               .takeRetainedValue() {
            metalLayer.colorspace = colorSpace
            configuredColorSpace = colorSpace
        } else {
            let fallback = CGColorSpace(name: CGColorSpace.sRGB)
            metalLayer.colorspace = fallback
            configuredColorSpace = fallback
        }

        let transfer = CVBufferCopyAttachment(
            pixelBuffer,
            kCVImageBufferTransferFunctionKey,
            nil
        ) as? String
        isHighDynamicRange = transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        if isHighDynamicRange {
            logger.notice("检测到 HDR 片源，Anime4K 档位改走通用超分")
        }
    }

    private func updateNominalFrameRateIfNeeded() {
        guard nominalVideoFrameRate == nil, let currentItem else { return }
        // 音轨的 currentVideoFrameRate 是 0，所以取最大值就等于「视频轨的帧率」，
        // 不用去碰已经废弃的同步版 AVAssetTrack.mediaType / nominalFrameRate。
        // 播放刚开始时它也是 0，这时就下一帧再试。
        let rate = currentItem.tracks.map(\.currentVideoFrameRate).max() ?? 0
        guard rate > 0 else { return }
        nominalVideoFrameRate = rate
        adaptivePolicy.updateConfiguration(.forVideoFrameRate(rate))
    }

    // MARK: - helpers

    private func makeTexture(from pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) -> (any MTLTexture)? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func makeIntermediateTexture(width: Int, height: Int) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
