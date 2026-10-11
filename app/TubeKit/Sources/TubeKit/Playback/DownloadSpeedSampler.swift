import Foundation

/// 根据 AVPlayer accessLog 的字节进度，平滑下行吞吐（B/s）。
///
/// - 仅在 `bytesTransferred` 增加时记入样本（证明有新下载）
/// - 样本值为 `observedBitrate / 8`（accessLog 单位是 bit/s）
/// - 保留最近 `maxSamples` 个样本做简单均值
/// - 超过 `staleAfter` 无新样本则输出 `nil`
public struct DownloadSpeedSampler: Sendable, Equatable {
    public var maxSamples: Int
    public var staleAfter: TimeInterval

    private var samples: [Double] = []
    private var lastBytes: Int64?
    private var lastSampleAt: TimeInterval?

    public init(maxSamples: Int = 3, staleAfter: TimeInterval = 2) {
        self.maxSamples = maxSamples
        self.staleAfter = staleAfter
    }

    /// - Parameters:
    ///   - bytesTransferred: accessLog 累计下载字节
    ///   - observedBitrate: accessLog `observedBitrate`（bit/s）
    ///   - time: 单调时间轴（秒），由调用方提供，便于测试
    @discardableResult
    public mutating func update(
        bytesTransferred: Int64,
        observedBitrate: Double,
        at time: TimeInterval
    ) -> Double? {
        if let lastSampleAt, time - lastSampleAt >= staleAfter {
            samples = []
        }

        if let lastBytes, bytesTransferred > lastBytes {
            let bps = observedBitrate / 8
            if bps >= 0 {
                samples.append(bps)
                if samples.count > maxSamples {
                    samples.removeFirst(samples.count - maxSamples)
                }
            }
            self.lastBytes = bytesTransferred
            self.lastSampleAt = time
        } else if lastBytes == nil {
            lastBytes = bytesTransferred
            // 锚定但不记样本；不更新 lastSampleAt，避免「假新鲜」
        }

        return currentSpeed(at: time)
    }

    public func currentSpeed(at time: TimeInterval) -> Double? {
        guard let lastSampleAt else { return nil }
        if time - lastSampleAt >= staleAfter {
            return nil
        }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    public mutating func reset() {
        samples = []
        lastBytes = nil
        lastSampleAt = nil
    }
}
