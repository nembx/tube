import Foundation
import Metal
import os

/// 把一条预设用到的所有 `.metal` 源码编译成 compute pipeline state。
///
/// ## 为什么是运行时编译
///
/// 常规做法是让 `.metal` 参与编译期构建，产出 `default.metallib`，运行时零开销。
/// 这里没走那条路，原因是它要求构建机装了 Metal 离线工具链
/// （`xcodebuild -downloadComponent MetalToolchain`，几 GB）。CezzuKit 是个
/// SwiftPM 包，`swift build` / `swift test` / CI 都不该有这个硬依赖。
///
/// 代价是首次使用要编译一次。实测（M 系列 Mac）每个 `.metal` 文件 130~270ms，
/// 一条预设 5~6 个文件大约 1 秒。所以这里的规矩是：
///
/// 1. **绝不在渲染路径上同步编译**。编译丢到后台队列，期间 `Anime4KScaler`
///    对外报「没准备好」，`VideoSuperResolutionPipeline` 退回 Lanczos ——
///    用户先看到画面，一秒后自动变锐利，不会卡帧。
/// 2. **进程内按预设缓存**。换集、换片源不会重编。
/// 3. **pipeline state 落盘缓存**（`MTLBinaryArchive`）。源码→AIR 每次都得走，
///    但 AIR→GPU 机器码这段能跨启动复用。
@MainActor
public final class Anime4KLibraryLoader {
    /// 编译产物：函数名 -> pipeline state。
    ///
    /// `MTLComputePipelineState` 按 Metal 的文档是线程安全的，只是 SDK 没给
    /// `Sendable` 标注。这个结构体建好之后就只读，跨隔离域传是安全的。
    public struct CompiledPreset: @unchecked Sendable {
        public let pipelineStates: [String: any MTLComputePipelineState]
        /// 收尾用的重采样 kernel。
        public let presentState: any MTLComputePipelineState
    }

    public enum LoadState {
        case idle
        case compiling
        case ready(CompiledPreset)
        case failed(String)
    }

    private let device: any MTLDevice
    private var states: [String: LoadState] = [:]
    private let logger = Logger(subsystem: "com.bent2685.cezzu", category: "Anime4K")

    /// Metal 的对象按官方文档是线程安全的，但 SDK 没给它们 `Sendable` 标注，
    /// 所以跨队列传递时套一层。这里只在后台队列上调 `makeLibrary` /
    /// `makeComputePipelineState`，都是 Metal 明确支持并发调用的接口。
    private struct DeviceBox: @unchecked Sendable {
        let device: any MTLDevice
    }

    private struct CompileResult: @unchecked Sendable {
        let pipelineStates: [String: any MTLComputePipelineState]
        let presentState: any MTLComputePipelineState
    }

    public init(device: any MTLDevice) {
        self.device = device
    }

    /// 取某个预设的编译产物。还没编好时返回 `nil` 并在后台启动编译。
    public func compiledPreset(for preset: Anime4KPreset) -> CompiledPreset? {
        switch states[preset.id] {
        case .ready(let compiled):
            return compiled
        case .compiling:
            return nil
        case .failed:
            // 失败过就不反复重试了 —— 失败原因（资源缺失 / 着色器语法错）重试也不会变，
            // 每帧重编只会把主线程拖垮。
            return nil
        case .idle, nil:
            startCompiling(preset)
            return nil
        }
    }

    /// 预热。用户在菜单里选中某个 Anime4K 档位时调用，这样等到真正开播时
    /// 编译大概率已经完成了。
    public func prewarm(_ preset: Anime4KPreset) {
        _ = compiledPreset(for: preset)
    }

    /// 某个预设是否已经编译失败。UI 可以据此把档位置灰。
    public func hasFailed(_ preset: Anime4KPreset) -> Bool {
        if case .failed = states[preset.id] { return true }
        return false
    }

    /// 还没编好时，是「正在编」还是「编失败了」—— 诊断读数要靠它区分，
    /// 前者等一会儿就好，后者不会自己恢复。
    public func pendingReason(
        for preset: Anime4KPreset
    ) -> SuperResolutionDiagnostics.FallbackReason? {
        switch states[preset.id] {
        case .ready: return nil
        case .failed: return .compileFailed
        case .compiling, .idle, nil: return .compiling
        }
    }

    // MARK: - private

    private func startCompiling(_ preset: Anime4KPreset) {
        let sources: [String]
        let functionNames: [String]
        do {
            let manifest = try Anime4KShaderCatalog.loadManifest()
            var collectedSources: [String] = []
            var collectedFunctions: [String] = []
            for id in preset.shaderIDs {
                guard let shader = manifest.shader(id: id) else {
                    throw Anime4KRenderPlanner.PlanError.unknownShader(id)
                }
                collectedSources.append(try Anime4KShaderCatalog.loadSource(named: shader.source))
                collectedFunctions.append(contentsOf: shader.passes.map(\.function))
            }
            collectedSources.append(try Anime4KShaderCatalog.loadSource(named: "Anime4KPresent.metal"))
            sources = collectedSources
            functionNames = collectedFunctions
        } catch {
            let message = String(describing: error)
            logger.error("Anime4K 资源加载失败 preset=\(preset.id, privacy: .public): \(message, privacy: .public)")
            states[preset.id] = .failed(message)
            return
        }

        states[preset.id] = .compiling
        let box = DeviceBox(device: device)
        let archiveURL = Self.binaryArchiveURL(preset: preset, device: device)
        let presetID = preset.id

        Task.detached(priority: .userInitiated) {
            let outcome = Self.compile(
                box: box,
                sources: sources,
                functionNames: functionNames,
                archiveURL: archiveURL
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch outcome {
                case .success(let result):
                    self.states[presetID] = .ready(
                        CompiledPreset(
                            pipelineStates: result.pipelineStates,
                            presentState: result.presentState
                        )
                    )
                    self.logger.info("Anime4K 预设编译完成 preset=\(presetID, privacy: .public) 函数数=\(result.pipelineStates.count)")
                case .failure(let error):
                    let message = String(describing: error)
                    self.states[presetID] = .failed(message)
                    self.logger.error("Anime4K 预设编译失败 preset=\(presetID, privacy: .public): \(message, privacy: .public)")
                }
            }
        }
    }

    /// 在后台队列上跑的纯编译过程。
    private nonisolated static func compile(
        box: DeviceBox,
        sources: [String],
        functionNames: [String],
        archiveURL: URL?
    ) -> Result<CompileResult, any Error> {
        let device = box.device
        do {
            var functions: [String: any MTLFunction] = [:]
            var presentFunction: (any MTLFunction)?

            for source in sources {
                let library = try device.makeLibrary(source: source, options: nil)
                for name in library.functionNames {
                    guard let function = library.makeFunction(name: name) else { continue }
                    if name == "a4k_present" {
                        presentFunction = function
                    } else {
                        functions[name] = function
                    }
                }
            }

            guard let presentFunction else {
                throw Anime4KShaderCatalog.LoadError.sourceMissing("a4k_present")
            }
            let missing = functionNames.filter { functions[$0] == nil }
            guard missing.isEmpty else {
                throw Anime4KShaderCatalog.LoadError.sourceMissing(missing.joined(separator: ", "))
            }

            let archive = Self.loadArchive(device: device, url: archiveURL)
            var states: [String: any MTLComputePipelineState] = [:]
            for name in functionNames {
                states[name] = try Self.makePipelineState(
                    device: device,
                    function: functions[name]!,
                    archive: archive
                )
            }
            let presentState = try Self.makePipelineState(
                device: device,
                function: presentFunction,
                archive: archive
            )

            Self.persistArchive(archive, to: archiveURL)
            return .success(CompileResult(pipelineStates: states, presentState: presentState))
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func makePipelineState(
        device: any MTLDevice,
        function: any MTLFunction,
        archive: (any MTLBinaryArchive)?
    ) throws -> any MTLComputePipelineState {
        guard let archive else {
            return try device.makeComputePipelineState(function: function)
        }
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = function
        descriptor.binaryArchives = [archive]
        do {
            let (state, _) = try device.makeComputePipelineState(
                descriptor: descriptor,
                options: []
            )
            // 归档里没命中时上面这趟是现编的，补进归档让下次启动能直接取。
            try? archive.addComputePipelineFunctions(descriptor: descriptor)
            return state
        } catch {
            return try device.makeComputePipelineState(function: function)
        }
    }

    private nonisolated static func loadArchive(
        device: any MTLDevice,
        url: URL?
    ) -> (any MTLBinaryArchive)? {
        let descriptor = MTLBinaryArchiveDescriptor()
        if let url, FileManager.default.fileExists(atPath: url.path) {
            descriptor.url = url
            if let archive = try? device.makeBinaryArchive(descriptor: descriptor) {
                return archive
            }
            // 归档坏了（换了系统版本 / 换了 GPU）就扔掉重建，不要让它一直挡路。
            try? FileManager.default.removeItem(at: url)
        }
        descriptor.url = nil
        return try? device.makeBinaryArchive(descriptor: descriptor)
    }

    private nonisolated static func persistArchive(_ archive: (any MTLBinaryArchive)?, to url: URL?) {
        guard let archive, let url else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? archive.serialize(to: url)
    }

    /// 归档路径按「预设 + GPU 名字」分开 —— 换设备（比如 Mac 外接 eGPU）时
    /// 旧归档没法用，混在一起只会每次都 miss。
    private nonisolated static func binaryArchiveURL(
        preset: Anime4KPreset,
        device: any MTLDevice
    ) -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let deviceSlug = device.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return caches
            .appendingPathComponent("Anime4K", isDirectory: true)
            .appendingPathComponent("\(preset.id)-\(deviceSlug).metallib")
    }
}
