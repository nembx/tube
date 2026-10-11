import Testing

@testable import TubeKit

@Suite("Anime4K 渲染图规划")
struct Anime4KRenderPlanTests {
    private func manifest() throws -> Anime4KManifest {
        try Anime4KShaderCatalog.loadManifest()
    }

    private func plan(
        _ preset: Anime4KPreset,
        from input: (Int, Int),
        to output: (Int, Int)
    ) throws -> Anime4KRenderPlan {
        try Anime4KRenderPlanner.plan(
            preset: preset,
            manifest: try manifest(),
            inputSize: Anime4KTextureSize(width: input.0, height: input.1),
            outputSize: Anime4KTextureSize(width: output.0, height: output.1)
        )
    }

    @Test("1080p 放到 1440p：跑一次 x2 放大再降回目标尺寸")
    func planUpscalesThenDownscalesToTarget() throws {
        let plan = try plan(.fast, from: (1920, 1080), to: (2560, 1440))

        // AutoDownscalePre_x2 会把放大后的 3840x2160 收回到目标尺寸，
        // 之后第二级放大的 //!WHEN 就不成立了 —— 这正是它存在的意义。
        #expect(plan.resultSize == Anime4KTextureSize(width: 2560, height: 1440))
        #expect(plan.passes.isEmpty == false)
        if case .input = plan.result {
            Issue.record("结果不该还停在原始输入上")
        }
    }

    @Test("倍率不到 1.2 时整条放大链被 WHEN 跳过")
    func skipsUpscaleBelowThreshold() throws {
        let plan = try plan(.fast, from: (1920, 1080), to: (2016, 1134))

        // 上游给每个放大 pass 都挂了 `OUTPUT.w MAIN.w / 1.200 >`，
        // 片源已经够清楚时不该白烧 GPU。
        #expect(plan.resultSize == Anime4KTextureSize(width: 1920, height: 1080))
        // Clamp_Highlights 没有 WHEN，所以还是会跑（2 个 MAIN + 1 个 PREKERNEL）。
        #expect(plan.passes.count == 3)
    }

    @Test("PREKERNEL 阶段的 pass 排在所有 MAIN 阶段之后")
    func prekernelRunsLast() throws {
        let manifest = try manifest()
        let plan = try plan(.highQuality, from: (1280, 720), to: (2560, 1440))

        let prekernelFunctions = Set(
            manifest.shaders
                .flatMap(\.passes)
                .filter { $0.hook == "PREKERNEL" }
                .map(\.function)
        )
        let indices = plan.passes.enumerated()
            .filter { prekernelFunctions.contains($0.element.function) }
            .map(\.offset)

        #expect(indices.isEmpty == false, "高质档应该包含 Clamp_Highlights 的去振铃 pass")
        // 去振铃必须在最后 —— 它要钳的是所有放大做完之后的高光。
        #expect(indices.allSatisfy { $0 >= plan.passes.count - indices.count })
    }

    @Test("被读的中间纹理一定在之前被写过")
    func everyReadIsPrecededByWrite() throws {
        for preset in Anime4KPreset.all {
            let plan = try plan(preset, from: (1920, 1080), to: (3840, 2160))
            var written = Set<Int>()
            for pass in plan.passes {
                for case .buffer(let index) in pass.inputs {
                    #expect(written.contains(index), "\(preset.id) 的 \(pass.function) 读了还没写过的 buffer \(index)")
                }
                written.insert(pass.output)
            }
        }
    }

    @Test("每张中间纹理恰好被释放一次")
    func everyBufferIsReleasedExactlyOnce() throws {
        for preset in Anime4KPreset.all {
            let plan = try plan(preset, from: (1920, 1080), to: (3840, 2160))
            let released = plan.passes.flatMap(\.releases)
            #expect(
                released.count == Set(released).count,
                "\(preset.id) 有 buffer 被重复释放"
            )
            // 最终结果那张不能被回收，其余的都该还回池子。
            var expected = Set(0..<plan.buffers.count)
            if case .buffer(let index) = plan.result { expected.remove(index) }
            #expect(Set(released) == expected, "\(preset.id) 的释放集合对不上")
        }
    }

    @Test("峰值显存按活跃集算，不是所有中间纹理求和")
    func peakBytesUsesLiveSet() throws {
        let plan = try plan(.highQuality, from: (1920, 1080), to: (3840, 2160))
        let naiveSum = plan.buffers.reduce(0) { $0 + $1.byteCount }
        #expect(plan.peakBufferBytes > 0)
        #expect(plan.peakBufferBytes < naiveSum, "峰值应当小于全部求和，否则活跃集分析没生效")
    }

    @Test("高质档的 Restore 会同时压住 7 张全分辨率中间纹理")
    func highQualityHoldsDenseSkipConnections() throws {
        let plan = try plan(.highQuality, from: (1920, 1080), to: (3840, 2160))
        // Restore_CNN_M 的最后一层要一次读 MAIN + 7 张 conv 输出，这是它显存占用的来源。
        // 数字变了说明上游换了网络结构，需要重新评估设备门槛。
        let widestPass = plan.passes.map(\.inputs.count).max()
        #expect(widestPass == 8)
    }

    // MARK: - 错误分支

    @Test("引用不存在的着色器会报错")
    func unknownShaderThrows() throws {
        let preset = Anime4KPreset(id: "bogus", shaderIDs: ["Anime4K_Does_Not_Exist"])
        #expect(throws: Anime4KRenderPlanner.PlanError.unknownShader("Anime4K_Does_Not_Exist")) {
            _ = try Anime4KRenderPlanner.plan(
                preset: preset,
                manifest: try manifest(),
                inputSize: Anime4KTextureSize(width: 1920, height: 1080),
                outputSize: Anime4KTextureSize(width: 3840, height: 2160)
            )
        }
    }

    @Test("尺寸为 0 会报错")
    func zeroSizeThrows() throws {
        let manifest = try manifest()
        #expect(throws: Anime4KRenderPlanner.PlanError.invalidInputSize) {
            _ = try Anime4KRenderPlanner.plan(
                preset: .fast,
                manifest: manifest,
                inputSize: .zero,
                outputSize: Anime4KTextureSize(width: 3840, height: 2160)
            )
        }
        #expect(throws: Anime4KRenderPlanner.PlanError.invalidInputSize) {
            _ = try Anime4KRenderPlanner.plan(
                preset: .fast,
                manifest: manifest,
                inputSize: Anime4KTextureSize(width: 1920, height: 1080),
                outputSize: .zero
            )
        }
    }
}
