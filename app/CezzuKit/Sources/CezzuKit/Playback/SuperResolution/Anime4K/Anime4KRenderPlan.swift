import Foundation

/// 渲染图里一张纹理的规格。纹理池按它做复用。
public struct Anime4KTextureSpec: Equatable, Hashable, Sendable {
    public let size: Anime4KTextureSize
    /// 1 或 4。1 通道的中间纹理（`Clamp_Highlights` 的统计图）用 r16f，省一半带宽。
    public let components: Int

    public init(size: Anime4KTextureSize, components: Int) {
        self.size = size
        self.components = components
    }

    /// 单张纹理的字节数，按 16-bit 浮点算。诊断和能力门槛判断要用。
    public var byteCount: Int {
        size.width * size.height * components * 2
    }
}

/// 一个 pass 的输入来源。
public enum Anime4KTextureRef: Equatable, Hashable, Sendable {
    /// 调用方传进来的原始输入纹理（也就是 `NATIVE`，以及还没被任何 pass 改写过的 `MAIN`）。
    case input
    /// 渲染图自己分配的第 n 张中间纹理。
    case buffer(Int)
}

/// 一个已经解出具体尺寸的 pass。
public struct Anime4KPlannedPass: Equatable, Sendable {
    /// Metal kernel 函数名。
    public let function: String
    /// 上游 `//!DESC`，出错时报给诊断用。
    public let desc: String
    /// 按 texture slot 顺序排列的输入。
    public let inputs: [Anime4KTextureRef]
    /// 输出写到第几张中间纹理。
    public let output: Int
    /// 跑完这个 pass 之后就没人再读的中间纹理，可以还回池子。
    public let releases: [Int]
}

/// 一次超分的完整执行计划。
///
/// 规划是纯计算 —— 不碰 Metal，不分配任何 GPU 资源，所以能完整单测。
/// 真正的纹理分配和 encode 在 `Anime4KScaler` 里。
public struct Anime4KRenderPlan: Equatable, Sendable {
    /// 所有中间纹理的规格，下标就是 `Anime4KTextureRef.buffer` 里的编号。
    public let buffers: [Anime4KTextureSpec]
    public let passes: [Anime4KPlannedPass]
    /// 最终结果在哪。所有 pass 都被 `//!WHEN` 跳过时它就是 `.input`。
    public let result: Anime4KTextureRef
    /// 最终结果的尺寸。可能和目标输出尺寸不等（`AutoDownscalePre` 只是尽量靠近），
    /// 差多少由 `Anime4KScaler` 用一次双线性重采样补上。
    public let resultSize: Anime4KTextureSize

    /// 峰值显存占用（字节）。用 `releases` 做活跃集分析，不是简单求和。
    public var peakBufferBytes: Int {
        var live = Set<Int>()
        var peak = 0
        for pass in passes {
            live.insert(pass.output)
            peak = max(peak, live.reduce(0) { $0 + buffers[$1].byteCount })
            for released in pass.releases { live.remove(released) }
        }
        return peak
    }
}

/// 把预设 + 输入/输出尺寸规划成一张可执行的渲染图。
public enum Anime4KRenderPlanner {
    public enum PlanError: Error, Equatable, Sendable {
        case unknownShader(String)
        case unknownTexture(pass: String, texture: String)
        case invalidInputSize
        case expression(pass: String, underlying: Anime4KSizeExpression.EvaluationError)
    }

    /// HOOK 阶段的执行顺序。mpv 会把同阶段的 hook 按注册顺序连着跑，跨阶段则按这个次序。
    /// Anime4K 只用到这两个阶段。
    static let stageOrder = ["MAIN", "PREKERNEL"]

    public static func plan(
        preset: Anime4KPreset,
        manifest: Anime4KManifest,
        inputSize: Anime4KTextureSize,
        outputSize: Anime4KTextureSize
    ) throws -> Anime4KRenderPlan {
        guard !inputSize.isEmpty, !outputSize.isEmpty else {
            throw PlanError.invalidInputSize
        }

        let shaders = try preset.shaderIDs.map { id -> Anime4KShaderManifest in
            guard let shader = manifest.shader(id: id) else { throw PlanError.unknownShader(id) }
            return shader
        }

        // 名字 -> 当前持有它的纹理。MAIN 一开始就是调用方给的输入。
        var bindings: [String: Anime4KTextureRef] = ["MAIN": .input, "NATIVE": .input]
        var sizes: [String: Anime4KTextureSize] = [
            "MAIN": inputSize,
            "NATIVE": inputSize,
            "OUTPUT": outputSize,
        ]

        var buffers: [Anime4KTextureSpec] = []
        var passes: [Anime4KPlannedPass] = []
        // buffer 下标 -> 最后一次被读到的 pass 下标。用来算 releases。
        var lastRead: [Int: Int] = [:]

        for stage in stageOrder {
            for shader in shaders {
                for manifestPass in shader.passes where manifestPass.hook == stage {
                    // //!WIDTH / //!WHEN 里可以直接写 `HOOKED.w` 或阶段名（`PREKERNEL.w`），
                    // 它们指的都是当前 hook 阶段那张纹理，得先补进符号表再求值。
                    let symbols = symbols(for: manifestPass, sizes: sizes)
                    guard try shouldRun(manifestPass, sizes: symbols) else { continue }

                    let outSize = try resolveSize(manifestPass, sizes: symbols)
                    let inputs = try manifestPass.binds.map { name -> Anime4KTextureRef in
                        let canonical = canonicalName(name, hook: manifestPass.hook)
                        guard let ref = bindings[canonical] else {
                            throw PlanError.unknownTexture(pass: manifestPass.function, texture: name)
                        }
                        return ref
                    }

                    // 读写同名（比如 depth-to-space 的 BIND MAIN + SAVE MAIN）必须换一张纹理，
                    // 不能原地读写，所以每个 pass 的输出一律新开一个 buffer 编号。
                    let outputIndex = buffers.count
                    buffers.append(
                        Anime4KTextureSpec(size: outSize, components: manifestPass.components)
                    )

                    let passIndex = passes.count
                    for case .buffer(let index) in inputs {
                        lastRead[index] = passIndex
                    }

                    passes.append(
                        Anime4KPlannedPass(
                            function: manifestPass.function,
                            desc: manifestPass.desc,
                            inputs: inputs,
                            output: outputIndex,
                            releases: []
                        )
                    )

                    let savedName = canonicalName(manifestPass.save, hook: manifestPass.hook)
                    bindings[savedName] = .buffer(outputIndex)
                    sizes[savedName] = outSize
                }
            }
        }

        let result = bindings["MAIN"] ?? .input
        let resultSize = sizes["MAIN"] ?? inputSize
        if case .buffer(let index) = result {
            // 结果纹理要活到最后，不能被回收。
            lastRead[index] = passes.count
        }

        return Anime4KRenderPlan(
            buffers: buffers,
            passes: attachReleases(to: passes, lastRead: lastRead),
            result: result,
            resultSize: resultSize
        )
    }

    // MARK: - private

    /// `HOOKED` 是「当前 hook 阶段那张纹理」的别名；而在我们这条线性流水线里，
    /// `PREKERNEL` 阶段操作的就是所有 MAIN 阶段 pass 跑完之后的 MAIN，
    /// 所以两个名字指向同一张纹理。
    static func canonicalName(_ name: String, hook: String) -> String {
        let resolved = name == "HOOKED" ? hook : name
        return resolved == "PREKERNEL" ? "MAIN" : resolved
    }

    /// 给某个 pass 求值用的符号表：在全局表基础上补上 `HOOKED` 和阶段名两个别名。
    private static func symbols(
        for pass: Anime4KPassManifest,
        sizes: [String: Anime4KTextureSize]
    ) -> [String: Anime4KTextureSize] {
        guard let hookedSize = sizes[canonicalName(pass.hook, hook: pass.hook)] else {
            return sizes
        }
        var symbols = sizes
        symbols["HOOKED"] = hookedSize
        symbols[pass.hook] = hookedSize
        return symbols
    }

    private static func shouldRun(
        _ pass: Anime4KPassManifest,
        sizes: [String: Anime4KTextureSize]
    ) throws -> Bool {
        do {
            return try Anime4KSizeExpression.evaluateCondition(pass.when, symbols: sizes)
        } catch let error as Anime4KSizeExpression.EvaluationError {
            throw PlanError.expression(pass: pass.function, underlying: error)
        }
    }

    private static func resolveSize(
        _ pass: Anime4KPassManifest,
        sizes: [String: Anime4KTextureSize]
    ) throws -> Anime4KTextureSize {
        do {
            return Anime4KTextureSize(
                width: try Anime4KSizeExpression.evaluateDimension(pass.width, symbols: sizes),
                height: try Anime4KSizeExpression.evaluateDimension(pass.height, symbols: sizes)
            )
        } catch let error as Anime4KSizeExpression.EvaluationError {
            throw PlanError.expression(pass: pass.function, underlying: error)
        }
    }

    /// 回填每个 pass 之后能释放哪些中间纹理。
    private static func attachReleases(
        to passes: [Anime4KPlannedPass],
        lastRead: [Int: Int]
    ) -> [Anime4KPlannedPass] {
        // buffer i 在 pass lastRead[i] 之后就没人读了。没被任何人读过的输出
        // （被 //!WHEN 跳过导致的死节点，或者最后一个 pass 的中间产物）当场就能放。
        var releasesByPass: [Int: [Int]] = [:]
        for (index, pass) in passes.enumerated() {
            let deadAt = lastRead[pass.output] ?? index
            releasesByPass[deadAt, default: []].append(pass.output)
        }
        return passes.enumerated().map { index, pass in
            Anime4KPlannedPass(
                function: pass.function,
                desc: pass.desc,
                inputs: pass.inputs,
                output: pass.output,
                releases: (releasesByPass[index] ?? []).sorted()
            )
        }
    }
}
