import Foundation

/// 一个 pass 的元数据，对应 `.glsl` 里那段 `//!` 指令头。
///
/// 这些字段是 `app/scripts/generate_anime4k_shaders.py` 在离线翻译时写进
/// `manifest.json` 的 —— 运行时不解析 GLSL。
public struct Anime4KPassManifest: Decodable, Equatable, Sendable {
    /// 上游 `//!DESC`，只用于日志和诊断。
    public let desc: String
    /// `//!HOOK`：`MAIN` 或 `PREKERNEL`。
    public let hook: String
    /// `//!BIND` 列表，顺序即 Metal 的 texture slot 顺序。
    public let binds: [String]
    /// `//!SAVE`，缺省时生成器已经填成 hook 阶段名。
    public let save: String
    /// `//!WIDTH` 的逆波兰 token。
    public let width: [String]
    /// `//!HEIGHT` 的逆波兰 token。
    public let height: [String]
    /// `//!COMPONENTS`，1 或 4，决定中间纹理是单通道还是四通道。
    public let components: Int
    /// `//!WHEN` 的逆波兰 token，空表示恒执行。
    public let when: [String]
    /// 生成的 Metal kernel 函数名。
    public let function: String
}

/// 一个 `.glsl` 文件翻译出来的一组 pass。
public struct Anime4KShaderManifest: Decodable, Equatable, Sendable {
    /// 上游文件名去掉扩展名，例如 `Anime4K_Upscale_CNN_x2_S`。预设用它引用着色器。
    public let id: String
    /// 生成的 `.metal` 文件名。
    public let source: String
    public let passes: [Anime4KPassManifest]
}

/// `manifest.json` 的根。
public struct Anime4KManifest: Decodable, Equatable, Sendable {
    /// 生成器允许的最大绑定数，必须和 `.metal` 里 `A4KUniforms` 的数组长度一致。
    /// 输出纹理固定挂在 `maxBinds` 这个 slot 上。
    public let maxBinds: Int
    public let shaders: [Anime4KShaderManifest]

    public func shader(id: String) -> Anime4KShaderManifest? {
        shaders.first { $0.id == id }
    }
}

/// 从 bundle 里加载 manifest 和 `.metal` 源码。
///
/// 着色器源码不在编译期进 metallib —— 见 `Anime4KLibraryLoader` 顶部对这个取舍的说明。
enum Anime4KShaderCatalog {
    enum LoadError: Error, Equatable, Sendable {
        case manifestMissing
        case sourceMissing(String)
        case decodeFailed(String)
    }

    /// 资源在 bundle 里的子目录。`Package.swift` 用 `.copy` 保留了目录结构。
    static let resourceSubdirectory = "Anime4K"

    /// 解析后的 manifest。加载失败时抛错而不是返回空 —— 这属于打包事故，
    /// 静默降级只会让问题更难查。
    static func loadManifest(bundle: Bundle = .module) throws -> Anime4KManifest {
        guard let url = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) else {
            throw LoadError.manifestMissing
        }
        do {
            return try JSONDecoder().decode(Anime4KManifest.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.decodeFailed(String(describing: error))
        }
    }

    /// 读某个着色器的 MSL 源码。
    static func loadSource(
        named source: String,
        bundle: Bundle = .module
    ) throws -> String {
        let name = (source as NSString).deletingPathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: "metal",
            subdirectory: resourceSubdirectory
        ) else {
            throw LoadError.sourceMissing(source)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LoadError.sourceMissing(source)
        }
    }
}
