import Testing
@testable import CezzuKit

@Suite("DownloadSpeedSampler")
struct DownloadSpeedSamplerTests {

    @Test("first observation only anchors and yields nil")
    func firstObservationAnchors() {
        var sampler = DownloadSpeedSampler()
        let speed = sampler.update(
            bytesTransferred: 1000,
            observedBitrate: 8_000_000,
            at: 0
        )
        #expect(speed == nil)
    }

    @Test("bytes increase records observedBitrate as B/s")
    func recordsObservedBitrateAsBytesPerSecond() {
        var sampler = DownloadSpeedSampler()
        _ = sampler.update(bytesTransferred: 1000, observedBitrate: 8_000_000, at: 0)
        let speed = sampler.update(bytesTransferred: 5000, observedBitrate: 8_000_000, at: 1)
        #expect(speed == 1_000_000)
    }

    @Test("averages the most recent samples")
    func averagesRecentSamples() {
        var sampler = DownloadSpeedSampler(maxSamples: 3)
        _ = sampler.update(bytesTransferred: 1, observedBitrate: 8_000, at: 0)
        _ = sampler.update(bytesTransferred: 2, observedBitrate: 8_000, at: 1) // 1000 B/s
        _ = sampler.update(bytesTransferred: 3, observedBitrate: 16_000, at: 2) // 2000 B/s
        let speed = sampler.update(bytesTransferred: 4, observedBitrate: 24_000, at: 3) // 3000 B/s
        #expect(speed == 2000)
    }

    @Test("drops to nil after stale interval without new bytes")
    func becomesNilWhenStale() {
        var sampler = DownloadSpeedSampler(staleAfter: 2)
        _ = sampler.update(bytesTransferred: 1, observedBitrate: 8_000_000, at: 0)
        _ = sampler.update(bytesTransferred: 2, observedBitrate: 8_000_000, at: 1)
        #expect(sampler.currentSpeed(at: 2.5) == 1_000_000)
        #expect(sampler.currentSpeed(at: 3.0) == nil)
        // no byte growth — still nil
        let speed = sampler.update(bytesTransferred: 2, observedBitrate: 8_000_000, at: 3.5)
        #expect(speed == nil)
    }

    @Test("new bytes after stale start a fresh average")
    func freshAverageAfterStale() {
        var sampler = DownloadSpeedSampler(staleAfter: 2)
        _ = sampler.update(bytesTransferred: 1, observedBitrate: 8_000, at: 0)
        _ = sampler.update(bytesTransferred: 2, observedBitrate: 8_000, at: 1) // 1000
        #expect(sampler.currentSpeed(at: 3) == nil)
        let speed = sampler.update(bytesTransferred: 3, observedBitrate: 24_000, at: 4) // 3000
        #expect(speed == 3000)
    }

    @Test("reset clears samples and anchor")
    func resetClearsState() {
        var sampler = DownloadSpeedSampler()
        _ = sampler.update(bytesTransferred: 1, observedBitrate: 8_000_000, at: 0)
        _ = sampler.update(bytesTransferred: 2, observedBitrate: 8_000_000, at: 1)
        sampler.reset()
        #expect(sampler.currentSpeed(at: 1.5) == nil)
        let speed = sampler.update(bytesTransferred: 100, observedBitrate: 8_000_000, at: 2)
        #expect(speed == nil)
    }
}
