import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TubeKit

@Suite("RemoteImageCache")
struct RemoteImageCacheTests {

    /// 生成一张真实可解码的 PNG —— 解码路径走 ImageIO，不该拿假数据糊弄。
    private static func pngData(size: Int = 4) -> Data {
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let image = context.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// 记录每个 URL 被真正下载了几次。
    private actor FetchCounter {
        private(set) var counts: [String: Int] = [:]
        func record(_ url: URL) { counts[url.absoluteString, default: 0] += 1 }
        func count(_ url: URL) -> Int { counts[url.absoluteString] ?? 0 }
        var total: Int { counts.values.reduce(0, +) }
    }

    private static let urlA = URL(string: "https://example.com/a.jpg")!
    private static let urlB = URL(string: "https://example.com/b.jpg")!

    @Test("second request for the same url is served from memory, not re-downloaded")
    func memoryHitSkipsDownload() async {
        let counter = FetchCounter()
        let png = Self.pngData()
        let cache = RemoteImageCache(fetch: { url in
            await counter.record(url)
            return png
        })

        let first = await cache.image(for: Self.urlA)
        let second = await cache.image(for: Self.urlA)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await counter.count(Self.urlA) == 1)
    }

    @Test("concurrent requests for one url coalesce into a single download")
    func concurrentRequestsCoalesce() async {
        let counter = FetchCounter()
        let png = Self.pngData()
        let cache = RemoteImageCache(fetch: { url in
            await counter.record(url)
            // 让并发方有机会在下载完成前进来
            try? await Task.sleep(nanoseconds: 20_000_000)
            return png
        })

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = await cache.image(for: Self.urlA) }
            }
        }

        #expect(await counter.count(Self.urlA) == 1)
    }

    @Test("cachedImage only reports what is already decoded in memory")
    func cachedImageReflectsMemoryOnly() async {
        let png = Self.pngData()
        let cache = RemoteImageCache(fetch: { _ in png })

        #expect(await cache.cachedImage(for: Self.urlA) == nil)
        _ = await cache.image(for: Self.urlA)
        #expect(await cache.cachedImage(for: Self.urlA) != nil)
        // 没请求过的 URL 不该凭空命中
        #expect(await cache.cachedImage(for: Self.urlB) == nil)
    }

    @Test("a failed download yields nil and is not cached")
    func failedDownloadIsNotCached() async {
        let counter = FetchCounter()
        let cache = RemoteImageCache(fetch: { url in
            await counter.record(url)
            return nil
        })

        #expect(await cache.image(for: Self.urlA) == nil)
        #expect(await cache.cachedImage(for: Self.urlA) == nil)
        // 没缓存，所以第二次会重新试
        _ = await cache.image(for: Self.urlA)
        #expect(await counter.count(Self.urlA) == 2)
    }

    @Test("undecodable bytes yield nil instead of a broken entry")
    func garbageDataIsRejected() async {
        let cache = RemoteImageCache(fetch: { _ in Data("not an image".utf8) })
        #expect(await cache.image(for: Self.urlA) == nil)
        #expect(await cache.cachedImage(for: Self.urlA) == nil)
    }

    @Test("memory is bounded: the oldest entry is evicted past the cap")
    func evictsOldestBeyondCap() async {
        let png = Self.pngData()
        let cache = RemoteImageCache(maxEntries: 2, fetch: { _ in png })

        let urls = (0..<3).map { URL(string: "https://example.com/\($0).jpg")! }
        for url in urls { _ = await cache.image(for: url) }

        #expect(await cache.cachedImage(for: urls[0]) == nil)
        #expect(await cache.cachedImage(for: urls[1]) != nil)
        #expect(await cache.cachedImage(for: urls[2]) != nil)
    }

    @Test("maxEntries below one is clamped rather than trapping")
    func degenerateCapIsClamped() async {
        let png = Self.pngData()
        let cache = RemoteImageCache(maxEntries: 0, fetch: { _ in png })
        #expect(await cache.image(for: Self.urlA) != nil)
        #expect(await cache.cachedImage(for: Self.urlA) != nil)
    }

    @Test("removeAll drops decoded images so the next request re-downloads")
    func removeAllClearsMemory() async {
        let counter = FetchCounter()
        let png = Self.pngData()
        let cache = RemoteImageCache(fetch: { url in
            await counter.record(url)
            return png
        })

        _ = await cache.image(for: Self.urlA)
        await cache.removeAll()
        #expect(await cache.cachedImage(for: Self.urlA) == nil)
        _ = await cache.image(for: Self.urlA)
        #expect(await counter.count(Self.urlA) == 2)
    }

    // MARK: - 同步命中

    /// 视图重建时要在同一帧内把已缓存的封面摆上去，不能再等一次 actor 跳转。
    @Test("a decoded image is visible to the synchronous lookup")
    func decodedImageIsVisibleSynchronously() async {
        let png = Self.pngData()
        let cache = RemoteImageCache(fetch: { _ in png })

        #expect(cache.cachedImageNow(for: Self.urlA) == nil)
        _ = await cache.image(for: Self.urlA)
        #expect(cache.cachedImageNow(for: Self.urlA) != nil)
        #expect(cache.cachedImageNow(for: Self.urlB) == nil)
    }

    @Test("a failed download leaves nothing behind for the synchronous lookup")
    func failedDownloadStaysOutOfTheSyncIndex() async {
        let cache = RemoteImageCache(fetch: { _ in nil })

        _ = await cache.image(for: Self.urlA)

        #expect(cache.cachedImageNow(for: Self.urlA) == nil)
    }

    /// 被淘汰 / 清空的条目不能还留在同步索引里，否则会摆出一张 actor 那边已经没有的图。
    @Test("eviction and removeAll clear the synchronous index too")
    func syncIndexFollowsEviction() async {
        let png = Self.pngData()
        let cache = RemoteImageCache(maxEntries: 1, fetch: { _ in png })

        _ = await cache.image(for: Self.urlA)
        _ = await cache.image(for: Self.urlB)
        #expect(cache.cachedImageNow(for: Self.urlA) == nil)
        #expect(cache.cachedImageNow(for: Self.urlB) != nil)

        await cache.removeAll()
        #expect(cache.cachedImageNow(for: Self.urlB) == nil)
    }
}
