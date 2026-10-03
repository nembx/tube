import Foundation
import Testing

@testable import CezzuKit

@Suite("Anime4K manifest 与预设")
struct Anime4KManifestTests {
    @Test("bundle 里的 manifest 能解出来")
    func loadsBundledManifest() throws {
        let manifest = try Anime4KShaderCatalog.loadManifest()
        #expect(manifest.shaders.isEmpty == false)
        #expect(manifest.maxBinds > 0)
    }

    @Test("预设引用的着色器都存在")
    func presetsReferenceExistingShaders() throws {
        let manifest = try Anime4KShaderCatalog.loadManifest()
        for preset in Anime4KPreset.all {
            for id in preset.shaderIDs {
                #expect(
                    manifest.shader(id: id) != nil,
                    "预设 \(preset.id) 引用了不存在的着色器 \(id)"
                )
            }
        }
    }

    @Test("每个着色器的 .metal 源码都在 bundle 里")
    func everyShaderHasSource() throws {
        let manifest = try Anime4KShaderCatalog.loadManifest()
        for shader in manifest.shaders {
            let source = try Anime4KShaderCatalog.loadSource(named: shader.source)
            #expect(source.contains("#include <metal_stdlib>"))
            for pass in shader.passes {
                #expect(
                    source.contains("kernel void \(pass.function)("),
                    "\(shader.source) 里缺少 kernel \(pass.function)"
                )
            }
        }
    }

    @Test("收尾用的 present kernel 也在")
    func presentShaderExists() throws {
        let source = try Anime4KShaderCatalog.loadSource(named: "Anime4KPresent.metal")
        #expect(source.contains("kernel void a4k_present("))
    }

    @Test("pass 元数据都在支持的范围内")
    func passMetadataIsSupported() throws {
        let manifest = try Anime4KShaderCatalog.loadManifest()
        for shader in manifest.shaders {
            for pass in shader.passes {
                #expect(
                    Anime4KRenderPlanner.stageOrder.contains(pass.hook),
                    "\(shader.id) 的 \(pass.function) 用了没支持的 HOOK 阶段 \(pass.hook)"
                )
                #expect(
                    pass.components == 1 || pass.components == 4,
                    "\(shader.id) 的 \(pass.function) COMPONENTS=\(pass.components)"
                )
                #expect(
                    pass.binds.count <= manifest.maxBinds,
                    "\(shader.id) 的 \(pass.function) 绑了 \(pass.binds.count) 张，超过 maxBinds"
                )
                #expect(pass.width.isEmpty == false)
                #expect(pass.height.isEmpty == false)
            }
        }
    }

    @Test("HOOKED / PREKERNEL 别名解析")
    func canonicalNameResolvesAliases() {
        #expect(Anime4KRenderPlanner.canonicalName("HOOKED", hook: "MAIN") == "MAIN")
        // PREKERNEL 阶段操作的就是所有 MAIN pass 跑完后的 MAIN，两个名字同一张纹理。
        #expect(Anime4KRenderPlanner.canonicalName("HOOKED", hook: "PREKERNEL") == "MAIN")
        #expect(Anime4KRenderPlanner.canonicalName("PREKERNEL", hook: "PREKERNEL") == "MAIN")
        #expect(Anime4KRenderPlanner.canonicalName("conv2d_tf", hook: "MAIN") == "conv2d_tf")
    }

    // MARK: - 错误分支

    @Test("坏掉的 JSON 解不出来")
    func malformedManifestFailsToDecode() {
        let data = Data(#"{"maxBinds": 8, "shaders": [{"id": 42}]}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Anime4KManifest.self, from: data)
        }
    }

    @Test("找不到的着色器源码会报错")
    func missingSourceThrows() {
        #expect(throws: Anime4KShaderCatalog.LoadError.sourceMissing("NotAShader.metal")) {
            try Anime4KShaderCatalog.loadSource(named: "NotAShader.metal")
        }
    }

    @Test("按 id 查不到的预设返回 nil")
    func unknownPresetIsNil() {
        #expect(Anime4KPreset.preset(id: "modeA-M") == .highQuality)
        #expect(Anime4KPreset.preset(id: "nope") == nil)
    }
}
