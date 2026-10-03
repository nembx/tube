import Testing

@testable import CezzuKit

@Suite("超分诊断读数")
struct SuperResolutionDiagnosticsTests {
    @Test("关着的时候只说未启用")
    func offReportsDisabled() {
        let diagnostics = SuperResolutionDiagnostics(requestedMode: .off, activeMode: .off)
        #expect(diagnostics.summary == "未启用")
        #expect(diagnostics.isDegraded == false)
    }

    @Test("正常跑的时候报尺寸、pass 数和显存")
    func activeReportsMetrics() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KFast,
            activeMode: .anime4KFast,
            inputSize: Anime4KTextureSize(width: 1920, height: 1080),
            outputSize: Anime4KTextureSize(width: 2083, height: 1179),
            passCount: 9,
            peakBufferBytes: 116 * 1_048_576,
            lastGPUMilliseconds: 6.24
        )
        // GPU 耗时刻意不进这行文字：它每帧都在变，放进来菜单会跟着一直重建，
        // 播放中拉开菜单能看到这一行不停闪。
        #expect(diagnostics.summary == "1920×1080 → 2083×1179 · 9 pass · 116MB")
        #expect(diagnostics.isDegraded == false)
    }

    @Test("降级时报的是退到哪一档以及为什么")
    func degradedReportsReason() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KHighQuality,
            activeMode: .efficiency,
            fallbackReason: .compiling,
            inputSize: Anime4KTextureSize(width: 1920, height: 1080),
            outputSize: Anime4KTextureSize(width: 3840, height: 2160)
        )
        // 这一行就是用来回答「我切了档位怎么看不出区别」的。
        #expect(diagnostics.summary == "退回效率（着色器编译中）")
        #expect(diagnostics.isDegraded)
    }

    @Test("每种降级原因都有中文说法")
    func everyReasonHasText() {
        let reasons: [SuperResolutionDiagnostics.FallbackReason] = [
            .compiling, .compileFailed, .planFailed, .highDynamicRange, .unsupported,
        ]
        for reason in reasons {
            #expect(reason.displayText.isEmpty == false)
        }
        #expect(SuperResolutionDiagnostics.FallbackReason.highDynamicRange.displayText == "HDR 片源")
    }

    @Test("刚开还没出帧时说准备中")
    func pendingFirstFrame() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KFast,
            activeMode: .anime4KFast
        )
        #expect(diagnostics.summary == "准备中")
    }

    @Test("非 Anime4K 档位不报 pass 数和显存")
    func nonAnime4KOmitsGraphMetrics() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .quality,
            activeMode: .quality,
            inputSize: Anime4KTextureSize(width: 1280, height: 720),
            outputSize: Anime4KTextureSize(width: 2560, height: 1440),
            lastGPUMilliseconds: 1.5
        )
        #expect(diagnostics.summary == "1280×720 → 2560×1440")
    }

    @Test("桥对象只在内容真的变了才写")
    @MainActor
    func bridgeSkipsIdenticalUpdates() {
        let bridge = SuperResolutionDiagnosticsBridge()
        #expect(bridge.diagnostics.requestedMode == .off)

        let value = SuperResolutionDiagnostics(requestedMode: .anime4KFast, activeMode: .anime4KFast)
        bridge.update(value)
        #expect(bridge.diagnostics == value)

        // 相同内容重复写不该产生新值 —— GPU 耗时每帧都在变，
        // 不去重的话菜单所在的视图树会一直重算。
        bridge.update(value)
        #expect(bridge.diagnostics == value)
    }

    // MARK: - 菜单标题里的紧凑读数

    @Test("关着时菜单标题不带后缀")
    func menuSummaryIsNilWhenOff() {
        #expect(SuperResolutionDiagnostics(requestedMode: .off).menuSummary == nil)
    }

    @Test("正常跑时菜单读数报尺寸和 pass 数")
    func menuSummaryReportsSizesAndPasses() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KFast,
            activeMode: .anime4KFast,
            inputSize: Anime4KTextureSize(width: 848, height: 480),
            outputSize: Anime4KTextureSize(width: 2083, height: 1179),
            passCount: 14,
            peakBufferBytes: 38 * 1_048_576
        )
        // 显存那项不进标题 —— 菜单标题放不下，日志里有。
        #expect(diagnostics.menuSummary == "848×480→2083×1179 · 14 pass")
    }

    @Test("被自适应策略降下来时读数说明是谁降的")
    func menuSummaryExplainsAdaptiveDowngrade() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KHighQuality,
            activeMode: .anime4KFast,
            fallbackReason: .gpuBudget
        )
        // 用户选的那一档不变，读数负责说明实际在跑哪档。
        #expect(diagnostics.menuSummary == "退回Anime4K 快速（GPU 超预算）")
        #expect(diagnostics.requestedMode == .anime4KHighQuality)
        #expect(diagnostics.isDegraded)
    }

    @Test("还没出帧时菜单读数说准备中")
    func menuSummaryPendingBeforeFirstFrame() {
        let diagnostics = SuperResolutionDiagnostics(
            requestedMode: .anime4KFast,
            activeMode: .anime4KFast
        )
        #expect(diagnostics.menuSummary == "准备中")
    }
}
