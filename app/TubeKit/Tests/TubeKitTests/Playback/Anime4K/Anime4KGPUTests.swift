import Foundation
import Metal
import Testing

@testable import TubeKit

/// 真机 GPU 上跑整条链的冒烟测试。
///
/// 这是唯一一处能证明「翻译出来的 MSL + 渲染图规划 + uniform 打包」三者对得上的测试 ——
/// 前面那些纯逻辑测试只管规划，不碰着色器。
///
/// 没有可用 GPU 时（部分 CI）整个 suite 直接跳过，和 `SuperResolutionModeTests`
/// 里对 `MTLCreateSystemDefaultDevice()` 的处理方式一致。
@Suite(
    "Anime4K GPU 端到端",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "需要可用的 Metal 设备")
)
struct Anime4KGPUTests {
    /// 编译一条预设并跑一帧，返回输出像素。
    @MainActor
    private func render(
        preset: Anime4KPreset,
        inputSize: Anime4KTextureSize,
        outputSize: Anime4KTextureSize,
        fill: (Int, Int) -> (Float, Float, Float)
    ) async throws -> [Float] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let loader = Anime4KLibraryLoader(device: device)
        let scaler = try #require(
            Anime4KVideoSuperResolutionScaler(device: device, preset: preset, loader: loader)
        )

        // 着色器是后台异步编译的，等它就绪。
        loader.prewarm(preset)
        var waited = 0
        while loader.compiledPreset(for: preset) == nil {
            #expect(loader.hasFailed(preset) == false, "预设 \(preset.id) 编译失败")
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
            #expect(waited < 300, "预设 \(preset.id) 编译超过 30 秒")
            if waited >= 300 { break }
        }

        let input = try #require(
            makeTexture(device, inputSize, format: .bgra8Unorm, write: false)
        )
        let output = try #require(
            makeTexture(device, outputSize, format: .bgra8Unorm, write: true)
        )

        // bgra8Unorm：内存里是 B, G, R, A
        var pixels = [UInt8](repeating: 0, count: inputSize.width * inputSize.height * 4)
        for y in 0..<inputSize.height {
            for x in 0..<inputSize.width {
                let (r, g, b) = fill(x, y)
                let offset = (y * inputSize.width + x) * 4
                pixels[offset] = UInt8(max(0, min(255, b * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, g * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, r * 255)))
                pixels[offset + 3] = 255
            }
        }
        pixels.withUnsafeBytes { raw in
            input.replace(
                region: MTLRegionMake2D(0, 0, inputSize.width, inputSize.height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: inputSize.width * 4
            )
        }

        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoded = scaler.encode(input: input, output: output, commandBuffer: commandBuffer)
        #expect(encoded, "encode 应该成功 —— 着色器已经编译完了")
        await commitAndWait(commandBuffer)
        #expect(commandBuffer.error == nil, "GPU 执行报错: \(String(describing: commandBuffer.error))")

        var result = [UInt8](repeating: 0, count: outputSize.width * outputSize.height * 4)
        result.withUnsafeMutableBytes { raw in
            output.getBytes(
                raw.baseAddress!,
                bytesPerRow: outputSize.width * 4,
                from: MTLRegionMake2D(0, 0, outputSize.width, outputSize.height),
                mipmapLevel: 0
            )
        }
        return result.map { Float($0) / 255 }
    }

    /// 提交并等待。
    ///
    /// `waitUntilCompleted()` 在 async 上下文里不可用，而 `completed()` 要求把
    /// 非 Sendable 的 command buffer 送进去，所以用完成回调把等待包一层 ——
    /// 只有 continuation 跨线程，command buffer 留在原地。
    ///
    /// 回调必须在 `commit()` 之前挂上，Metal 对此有断言。
    @MainActor
    private func commitAndWait(_ commandBuffer: any MTLCommandBuffer) async {
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
    }

    private func makeTexture(
        _ device: any MTLDevice,
        _ size: Anime4KTextureSize,
        format: MTLPixelFormat,
        write: Bool
    ) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: size.width,
            height: size.height,
            mipmapped: false
        )
        descriptor.usage = write ? [.shaderRead, .shaderWrite] : [.shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    @Test("快速档能跑完整条链并产出合法像素")
    @MainActor
    func fastPresetRenders() async throws {
        let input = Anime4KTextureSize(width: 160, height: 90)
        let output = Anime4KTextureSize(width: 320, height: 180)
        // 斜条纹：既有平坦区又有硬边，正好压 Anime4K 关心的线条。
        let pixels = try await render(preset: .fast, inputSize: input, outputSize: output) { x, y in
            let on = ((x + y) / 4) % 2 == 0
            return on ? (0.9, 0.9, 0.9) : (0.1, 0.1, 0.15)
        }

        #expect(pixels.count == output.width * output.height * 4)
        #expect(pixels.allSatisfy { $0.isFinite })
        // present kernel 会把 CNN 残差推出去的值钳回 [0,1]。
        #expect(pixels.allSatisfy { $0 >= 0 && $0 <= 1 })

        // 输出必须还有对比度 —— 全灰 / 全黑说明链路某处把画面吃掉了。
        let luma = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 2] }
        let minimum = try #require(luma.min())
        let maximum = try #require(luma.max())
        #expect(maximum - minimum > 0.3, "输出对比度塌了：\(minimum)...\(maximum)")
    }

    @Test("高质档能跑完整条链")
    @MainActor
    func highQualityPresetRenders() async throws {
        let input = Anime4KTextureSize(width: 128, height: 72)
        let output = Anime4KTextureSize(width: 256, height: 144)
        let pixels = try await render(
            preset: .highQuality,
            inputSize: input,
            outputSize: output
        ) { x, _ in
            let on = (x / 3) % 2 == 0
            return on ? (0.85, 0.2, 0.2) : (0.15, 0.15, 0.6)
        }

        #expect(pixels.count == output.width * output.height * 4)
        #expect(pixels.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })

        let red = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 2] }
        let blue = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
        // 竖条纹的颜色分布应当被保住：红条和蓝条不该混成一片。
        #expect((red.max() ?? 0) - (red.min() ?? 0) > 0.3)
        #expect((blue.max() ?? 0) - (blue.min() ?? 0) > 0.3)
    }

    @Test("平坦画面进去还是平坦画面出来")
    @MainActor
    func flatInputStaysFlat() async throws {
        let input = Anime4KTextureSize(width: 64, height: 64)
        let output = Anime4KTextureSize(width: 128, height: 128)
        let pixels = try await render(preset: .fast, inputSize: input, outputSize: output) { _, _ in
            (0.5, 0.5, 0.5)
        }

        // 纯色块上 CNN 不该凭空造出纹理。放宽到 0.06 是给 8 位量化和
        // 边缘 clamp 留的余量 —— 真出问题时（比如权重矩阵转置错了）偏差会大得多。
        let luma = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 2] }
        let minimum = try #require(luma.min())
        let maximum = try #require(luma.max())
        #expect(maximum - minimum < 0.06, "平坦区出现了不该有的纹理：\(minimum)...\(maximum)")
    }

    @Test("尺寸变化时会重新规划")
    @MainActor
    func replansOnSizeChange() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let loader = Anime4KLibraryLoader(device: device)
        let scaler = try #require(
            Anime4KVideoSuperResolutionScaler(device: device, preset: .fast, loader: loader)
        )
        loader.prewarm(.fast)
        var waited = 0
        while loader.compiledPreset(for: .fast) == nil, waited < 300 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try #require(loader.compiledPreset(for: .fast) != nil)

        for (inputSize, outputSize) in [
            (Anime4KTextureSize(width: 160, height: 90), Anime4KTextureSize(width: 320, height: 180)),
            (Anime4KTextureSize(width: 128, height: 72), Anime4KTextureSize(width: 200, height: 113)),
        ] {
            let input = try #require(makeTexture(device, inputSize, format: .bgra8Unorm, write: false))
            let output = try #require(makeTexture(device, outputSize, format: .bgra8Unorm, write: true))
            let commandBuffer = try #require(queue.makeCommandBuffer())
            #expect(scaler.encode(input: input, output: output, commandBuffer: commandBuffer))
            await commitAndWait(commandBuffer)
            #expect(commandBuffer.error == nil)
            #expect(scaler.peakBufferBytes > 0)
        }
    }

    @Test("着色器还没编好时报未就绪，让调用方走备胎")
    @MainActor
    func reportsNotReadyBeforeCompilation() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let loader = Anime4KLibraryLoader(device: device)
        let scaler = try #require(
            Anime4KVideoSuperResolutionScaler(device: device, preset: .fast, loader: loader)
        )

        let size = Anime4KTextureSize(width: 64, height: 64)
        let input = try #require(makeTexture(device, size, format: .bgra8Unorm, write: false))
        let output = try #require(
            makeTexture(device, Anime4KTextureSize(width: 128, height: 128), format: .bgra8Unorm, write: true)
        )
        let commandBuffer = try #require(queue.makeCommandBuffer())

        // 第一次调用只会触发后台编译，同帧不可能就绪 —— 必须返回 false，
        // 否则 pipeline 会把一张空纹理送去显示。
        #expect(scaler.encode(input: input, output: output, commandBuffer: commandBuffer) == false)
        commandBuffer.commit()
    }
}
