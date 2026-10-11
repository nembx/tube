import Foundation
import Testing
@testable import TubeKit

@Suite("PlaybackDiagnosticsBuilder")
struct PlaybackDiagnosticsTests {

    private func event(
        startupTime: TimeInterval = -1,
        stalls: Int = 0,
        indicated: Double = -1,
        observed: Double = -1,
        bytes: Int64 = 0
    ) -> PlaybackDiagnosticsBuilder.Event {
        .init(
            startupTime: startupTime,
            numberOfStalls: stalls,
            indicatedBitrate: indicated,
            observedBitrate: observed,
            numberOfBytesTransferred: bytes
        )
    }

    @Test("no events means nothing measured yet")
    func emptyLog() {
        #expect(PlaybackDiagnosticsBuilder.make(from: []) == .empty)
    }

    @Test("startup time is taken from the first event that has one")
    func startupComesFromFirstValidEvent() {
        let result = PlaybackDiagnosticsBuilder.make(from: [
            event(startupTime: -1),
            event(startupTime: 1.8),
            event(startupTime: 9.9),
        ])

        // 起播只发生一次；后面的事件即便带了数也不该覆盖它。
        #expect(result.startupSeconds == 1.8)
    }

    @Test("stalls accumulate across the whole session")
    func stallsAccumulate() {
        let result = PlaybackDiagnosticsBuilder.make(from: [
            event(stalls: 1),
            event(stalls: 0),
            event(stalls: 3),
        ])

        #expect(result.stallCount == 4)
    }

    @Test("bitrates report the latest valid reading")
    func bitratesTakeLatest() {
        let result = PlaybackDiagnosticsBuilder.make(from: [
            event(indicated: 1_000_000, observed: 900_000),
            event(indicated: 2_500_000, observed: 2_100_000),
            event(indicated: -1, observed: -1),
        ])

        // 码率反映的是"现在在放哪一档"，无效读数不该把它抹掉。
        #expect(result.indicatedBitrate == 2_500_000)
        #expect(result.observedBitrate == 2_100_000)
    }

    @Test("unavailable readings are ignored rather than recorded as zero")
    func ignoresUnavailableReadings() {
        let result = PlaybackDiagnosticsBuilder.make(from: [
            event(startupTime: .nan, indicated: .nan, observed: .nan, bytes: -1)
        ])

        #expect(result.startupSeconds == nil)
        #expect(result.indicatedBitrate == nil)
        #expect(result.observedBitrate == nil)
        #expect(result.transferredBytes == 0)
    }

    @Test("transferred bytes add up")
    func bytesAccumulate() {
        let result = PlaybackDiagnosticsBuilder.make(from: [
            event(bytes: 1024),
            event(bytes: 2048),
        ])

        #expect(result.transferredBytes == 3072)
    }
}

@Suite("AVPlayerBackend diagnostics")
@MainActor
struct AVPlayerBackendDiagnosticsTests {

    @Test("a fresh backend reports nothing measured")
    func startsEmpty() {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        #expect(backend.diagnostics == .empty)
    }

    @Test("loading a new item clears the previous session's numbers")
    func loadResetsDiagnostics() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )

        #expect(backend.diagnostics == .empty)
    }
}
