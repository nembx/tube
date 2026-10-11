import AVFoundation
import Testing
@testable import TubeKit

@Suite("AVPlayerBackend buffering configuration")
@MainActor
struct AVPlayerBackendBufferingTests {

    @Test("player waits rather than stalling")
    func waitsToMinimizeStalling() {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        #expect(backend.player.automaticallyWaitsToMinimizeStalling)
    }

    @Test("a freshly loaded item starts on the cheap startup buffer")
    func startupBufferIsRequested() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )

        let policy = backend.bufferingPolicy
        #expect(
            backend.player.currentItem?.preferredForwardBufferDuration
                == policy.forwardBufferSeconds(at: .startup)
        )
        #expect(
            backend.player.currentItem?.preferredPeakBitRate
                == policy.peakBitRate(at: .startup)
        )
    }

    @Test("seeking puts the item back on the startup buffer")
    func seekReturnsToStartupBuffer() async {
        let policy = PlayerBufferingPolicy(
            startupForwardBufferSeconds: 3,
            steadyForwardBufferSeconds: 45,
            startupPeakBitRate: 1_000_000,
            steadyPeakBitRate: 0
        )
        let backend = AVPlayerBackend(bufferingPolicy: policy)
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )
        // 手动推到稳态，再确认跳转把参数收回起播值。
        backend.player.currentItem?.preferredForwardBufferDuration = 45
        await backend.seek(to: 120)

        #expect(backend.player.currentItem?.preferredForwardBufferDuration == 3)
        #expect(backend.player.currentItem?.preferredPeakBitRate == 1_000_000)
    }

    @Test("unload clears the item and its buffered time")
    func unloadClearsItem() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )
        backend.unload()

        #expect(backend.player.currentItem == nil)
        #expect(backend.bufferedTime == nil)
    }

    @Test("loading with a resume position does not block on the seek")
    func resumePositionDoesNotBlockLoad() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 120
        )

        // 续播跳转是下发出去就返回的，装载不该把自己留在 seek 中的状态里 ——
        // 否则调用方的 play() 要排在整段缓冲之后，第一帧被一路推迟。
        #expect(backend.player.currentItem != nil)
        #expect(backend.isBuffering == false)
    }
}
