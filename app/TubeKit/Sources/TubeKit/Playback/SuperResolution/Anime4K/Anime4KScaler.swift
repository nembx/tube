import Foundation
import Metal
import os

/// Anime4K 档位的 `VideoSuperResolutionScaler` 实现。
///
/// 协议是「单帧、一次 encode」的形状，Anime4K 却是十几个 pass 的渲染图 ——
/// 两者并不冲突：所有 pass 都编进调用方给的同一个 `MTLCommandBuffer`，
/// 中间纹理由本类自己的 `Anime4KTexturePool` 管，对外仍然只是一次 `encode`。
/// 所以 `VideoSuperResolutionScaler` 协议一行都不用改。
///
/// 返回 `false` 的两种情况，调用方都应该退回 Lanczos 那条路：
/// - 着色器还在后台编译（首次使用的头一秒）
/// - 规划失败（尺寸异常 / manifest 有问题），这种会打一次日志然后一直 false
final class Anime4KVideoSuperResolutionScaler: VideoSuperResolutionScaler {
    private let device: any MTLDevice
    private let preset: Anime4KPreset
    private let loader: Anime4KLibraryLoader
    private let pool: Anime4KTexturePool
    private let manifest: Anime4KManifest
    private let logger = Logger(subsystem: "com.nembx.tube", category: "Anime4K")

    private var plan: Anime4KRenderPlan?
    private var planInputSize: Anime4KTextureSize = .zero
    private var planOutputSize: Anime4KTextureSize = .zero
    /// 规划失败过就不再反复尝试 —— 输入尺寸不变的话结果也不会变。
    private var planningFailed = false

    init?(device: any MTLDevice, preset: Anime4KPreset, loader: Anime4KLibraryLoader) {
        guard let manifest = try? Anime4KShaderCatalog.loadManifest() else { return nil }
        self.device = device
        self.preset = preset
        self.loader = loader
        self.manifest = manifest
        self.pool = Anime4KTexturePool(device: device)
    }

    /// 峰值中间纹理占用（字节）。诊断和 UI 提示用，没规划过时是 0。
    var peakBufferBytes: Int { plan?.peakBufferBytes ?? 0 }

    /// 渲染图里实际会执行的 pass 数（已经扣掉被 //!WHEN 跳过的）。
    var passCount: Int { plan?.passes.count ?? 0 }

    /// 规划失败过没有。诊断要区分「还没编好」和「规划就挂了」。
    var hasPlanningFailed: Bool { planningFailed }

    func encode(
        input: any MTLTexture,
        output: any MTLTexture,
        commandBuffer: any MTLCommandBuffer
    ) -> Bool {
        guard let compiled = loader.compiledPreset(for: preset) else { return false }

        let inputSize = Anime4KTextureSize(width: input.width, height: input.height)
        let outputSize = Anime4KTextureSize(width: output.width, height: output.height)

        guard let plan = resolvePlan(inputSize: inputSize, outputSize: outputSize) else {
            return false
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        encoder.label = "Anime4K \(preset.id)"

        var textures: [Int: any MTLTexture] = [:]
        var ok = true

        for pass in plan.passes {
            guard let state = compiled.pipelineStates[pass.function] else {
                logger.error("Anime4K 缺少 kernel \(pass.function, privacy: .public)")
                ok = false
                break
            }
            let spec = plan.buffers[pass.output]
            guard let destination = pool.acquire(spec) else {
                logger.error("Anime4K 中间纹理分配失败 \(spec.size.width, privacy: .public)x\(spec.size.height, privacy: .public)")
                ok = false
                break
            }
            textures[pass.output] = destination

            encoder.setComputePipelineState(state)
            for (slot, ref) in pass.inputs.enumerated() {
                encoder.setTexture(texture(for: ref, input: input, textures: textures), index: slot)
            }
            encoder.setTexture(destination, index: manifest.maxBinds)

            var uniforms = makeUniforms(
                pass: pass,
                plan: plan,
                inputSize: inputSize,
                outputSize: spec.size
            )
            encoder.setBytes(&uniforms, length: uniforms.count * MemoryLayout<Float>.size, index: 0)

            dispatch(encoder: encoder, state: state, size: spec.size)

            for released in pass.releases where released != pass.output {
                if let texture = textures.removeValue(forKey: released) {
                    pool.release(texture, spec: plan.buffers[released])
                }
            }
        }

        if ok {
            let source = texture(for: plan.result, input: input, textures: textures)
            encoder.setComputePipelineState(compiled.presentState)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(output, index: 1)
            dispatch(
                encoder: encoder,
                state: compiled.presentState,
                size: Anime4KTextureSize(width: output.width, height: output.height)
            )
        }

        encoder.endEncoding()

        // 这一帧用过的纹理全部还回池子。GPU 还没跑完就还回去是安全的：
        // 下一帧要重新 acquire 时会拿到同一批纹理，而下一帧的命令排在这一帧之后，
        // 同一个队列上顺序执行，不会重叠写。
        for (index, texture) in textures {
            pool.release(texture, spec: plan.buffers[index])
        }

        return ok
    }

    // MARK: - private

    private func resolvePlan(
        inputSize: Anime4KTextureSize,
        outputSize: Anime4KTextureSize
    ) -> Anime4KRenderPlan? {
        if let plan, planInputSize == inputSize, planOutputSize == outputSize {
            return plan
        }
        if planningFailed, planInputSize == inputSize, planOutputSize == outputSize {
            return nil
        }

        planInputSize = inputSize
        planOutputSize = outputSize
        pool.drain()

        do {
            let newPlan = try Anime4KRenderPlanner.plan(
                preset: preset,
                manifest: manifest,
                inputSize: inputSize,
                outputSize: outputSize
            )
            plan = newPlan
            planningFailed = false
            logger.info(
                """
                Anime4K 规划完成 preset=\(self.preset.id, privacy: .public) \
                \(inputSize.width, privacy: .public)x\(inputSize.height, privacy: .public) -> \
                \(newPlan.resultSize.width, privacy: .public)x\(newPlan.resultSize.height, privacy: .public) \
                (目标 \(outputSize.width, privacy: .public)x\(outputSize.height, privacy: .public)) \
                pass=\(newPlan.passes.count, privacy: .public) 峰值显存=\(newPlan.peakBufferBytes / 1_048_576, privacy: .public)MB
                """
            )
            return newPlan
        } catch {
            plan = nil
            planningFailed = true
            logger.error("Anime4K 规划失败: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func texture(
        for ref: Anime4KTextureRef,
        input: any MTLTexture,
        textures: [Int: any MTLTexture]
    ) -> any MTLTexture {
        switch ref {
        case .input:
            return input
        case .buffer(let index):
            // 规划保证了每个被读的 buffer 都在它之前被写过，所以这里取不到只可能是
            // 上面某个 pass 已经 break 掉了；退回原始输入至少不会崩。
            return textures[index] ?? input
        }
    }

    /// 按 `.metal` 里 `A4KUniforms` 的内存布局手工打包：
    /// `float2 texSize[maxBinds]` + `float2 texPt[maxBinds]` + `float2 outSize` + `float2 pad`。
    private func makeUniforms(
        pass: Anime4KPlannedPass,
        plan: Anime4KRenderPlan,
        inputSize: Anime4KTextureSize,
        outputSize: Anime4KTextureSize
    ) -> [Float] {
        let slots = manifest.maxBinds
        var values = [Float](repeating: 0, count: slots * 2 + slots * 2 + 2 + 2)

        for (slot, ref) in pass.inputs.enumerated() where slot < slots {
            let size: Anime4KTextureSize
            switch ref {
            case .input: size = inputSize
            case .buffer(let index): size = plan.buffers[index].size
            }
            values[slot * 2] = Float(size.width)
            values[slot * 2 + 1] = Float(size.height)
            values[slots * 2 + slot * 2] = 1.0 / Float(size.width)
            values[slots * 2 + slot * 2 + 1] = 1.0 / Float(size.height)
        }

        values[slots * 4] = Float(outputSize.width)
        values[slots * 4 + 1] = Float(outputSize.height)
        return values
    }

    private func dispatch(
        encoder: any MTLComputeCommandEncoder,
        state: any MTLComputePipelineState,
        size: Anime4KTextureSize
    ) {
        // 用「均匀 threadgroup + kernel 内边界判断」而不是 dispatchThreads，
        // 免得依赖非均匀 threadgroup 特性（生成的 kernel 里已经有边界判断了）。
        let width = min(state.threadExecutionWidth, state.maxTotalThreadsPerThreadgroup)
        let height = max(1, state.maxTotalThreadsPerThreadgroup / max(1, width))
        let threadgroup = MTLSize(width: width, height: min(height, 16), depth: 1)
        let groups = MTLSize(
            width: (size.width + threadgroup.width - 1) / threadgroup.width,
            height: (size.height + threadgroup.height - 1) / threadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadgroup)
    }
}
