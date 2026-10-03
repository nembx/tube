import AVFoundation
import CoreGraphics
import Observation

/// 拖拽进度条时的画面预览。
///
/// 用 `AVAssetImageGenerator` 抽帧，容差放到 ±2 秒让它直接吃最近的关键帧 ——
/// 精确抽帧要解码整个 GOP，拖拽时根本跟不上手。
/// HLS / 反代流上抽帧可能整段失败，那时保留上一张图，调用方回落到只显示时间。
///
/// 抽帧走的是一份**独立的** asset：跟正在播的那个共用会让缩略图的取流挤进播放
/// 自己的加载队列。同时全程只允许一张在路上（见 `ScrubPreviewRequestQueue`）。
@MainActor
@Observable
public final class PlayerScrubPreviewController {

    public private(set) var image: CGImage?

    private var generator: AVAssetImageGenerator?
    private var queue = ScrubPreviewRequestQueue()
    private var task: Task<Void, Never>?
    private static let maximumSize = CGSize(width: 320, height: 180)
    private static let tolerance = CMTime(seconds: 2, preferredTimescale: 600)

    public init() {}

    /// 用播放地址另开一份 asset 专门抽帧。
    public func prepare(url: URL?, headers: [String: String] = [:]) {
        reset()
        guard let url else { return }
        let asset =
            headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        generator.requestedTimeToleranceBefore = Self.tolerance
        generator.requestedTimeToleranceAfter = Self.tolerance
        self.generator = generator
    }

    public func request(at seconds: TimeInterval) {
        guard generator != nil, let target = queue.request(at: seconds) else { return }
        startGeneration(at: target)
    }

    public func reset() {
        task?.cancel()
        task = nil
        generator?.cancelAllCGImageGeneration()
        generator = nil
        queue.reset()
        image = nil
    }

    private func startGeneration(at seconds: TimeInterval) {
        guard let generator else { return }
        task = Task { [weak self] in
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            // 走回调式 API：AVAssetImageGenerator 不是 Sendable，async 版本没法跨隔离域传。
            let cgImage = await withCheckedContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                    continuation.resume(returning: image)
                }
            }
            guard !Task.isCancelled, let self else { return }
            if let cgImage {
                self.image = cgImage
            }
            // 这张回来了才去取手指最新停的位置 —— 中间那些注定被丢弃的落点不发请求。
            if let next = self.queue.finish() {
                self.startGeneration(at: next)
            }
        }
    }
}
