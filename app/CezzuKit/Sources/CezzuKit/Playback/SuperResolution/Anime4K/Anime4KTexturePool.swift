import Foundation
import Metal

/// 中间纹理的复用池。
///
/// Anime4K 的 M 档一趟要用十几张中间纹理，其中 Restore 的最后一层还要同时读
/// 7 张全分辨率的（1080p 下约 116MB）。每帧重新 `makeTexture` 会把分配器打爆，
/// 所以按规格缓存复用；`Anime4KRenderPlan` 算出来的 `releases` 决定什么时候还回来。
final class Anime4KTexturePool {
    private let device: any MTLDevice
    private var available: [Anime4KTextureSpec: [any MTLTexture]] = [:]

    init(device: any MTLDevice) {
        self.device = device
    }

    func acquire(_ spec: Anime4KTextureSpec) -> (any MTLTexture)? {
        if var bucket = available[spec], let texture = bucket.popLast() {
            available[spec] = bucket
            return texture
        }
        return makeTexture(spec)
    }

    func release(_ texture: any MTLTexture, spec: Anime4KTextureSpec) {
        available[spec, default: []].append(texture)
    }

    /// 清空池子。换片源 / 换档位 / 收到内存警告时调用。
    func drain() {
        available.removeAll()
    }

    /// 池子里当前缓存了多少字节。诊断用。
    var cachedByteCount: Int {
        available.reduce(0) { $0 + $1.key.byteCount * $1.value.count }
    }

    private func makeTexture(_ spec: Anime4KTextureSpec) -> (any MTLTexture)? {
        // 1 通道的中间纹理（Clamp_Highlights 的高光统计图）用 r16f，省一半带宽。
        let format: MTLPixelFormat = spec.components == 1 ? .r16Float : .rgba16Float
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: spec.size.width,
            height: spec.size.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
