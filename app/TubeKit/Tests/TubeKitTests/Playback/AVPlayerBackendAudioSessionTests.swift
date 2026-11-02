import Foundation
import Testing
@testable import TubeKit

@Suite("AVPlayerBackend 音频会话时机")
@MainActor
struct AVPlayerBackendAudioSessionTests {

    @MainActor
    final class RecordingAudioSession: PlaybackAudioSessionControlling {
        var events: [String] = []
        func activate() { events.append("activate") }
        func deactivate() { events.append("deactivate") }
    }

    @Test("创建和装载都不激活会话：放着歌点进来翻页不该把歌掐掉")
    func doesNotActivateBeforePlay() async {
        let session = RecordingAudioSession()
        let backend = AVPlayerBackend(audioSession: session)
        await backend.load(url: URL(string: "https://example.com/a.m3u8")!, headers: [:], startAt: 0)

        #expect(session.events.isEmpty)
        backend.dispose()
    }

    @Test("起播时才激活")
    func activatesOnPlay() {
        let session = RecordingAudioSession()
        let backend = AVPlayerBackend(audioSession: session)

        backend.play()

        #expect(session.events == ["activate"])
        backend.dispose()
    }

    @Test("非零倍速等于起播，同样激活；归零不激活")
    func activatesOnPositiveRate() {
        let session = RecordingAudioSession()
        let backend = AVPlayerBackend(audioSession: session)

        backend.setRate(1.5)
        #expect(session.events == ["activate"])

        backend.setRate(0)
        #expect(session.events == ["activate"])
        backend.dispose()
    }

    @Test("暂停不交还会话，收起时才交还")
    func deactivatesOnlyOnDispose() {
        let session = RecordingAudioSession()
        let backend = AVPlayerBackend(audioSession: session)

        backend.play()
        backend.pause()
        #expect(session.events == ["activate"])

        backend.dispose()
        #expect(session.events == ["activate", "deactivate"])
    }
}
