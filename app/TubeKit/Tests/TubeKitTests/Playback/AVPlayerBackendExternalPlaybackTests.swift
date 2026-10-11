import Testing
@testable import TubeKit

@Suite("AVPlayerBackend 投屏状态")
@MainActor
struct AVPlayerBackendExternalPlaybackTests {

    @Test("初始状态不在投屏")
    func initiallyInactive() {
        let backend = AVPlayerBackend()
        #expect(backend.isExternalPlaybackActive == false)
        backend.dispose()
    }

    @Test("翻转为投屏中会回调一次")
    func notifiesOnActivation() {
        let backend = AVPlayerBackend()
        var received: [Bool] = []
        backend.onExternalPlaybackChange = { received.append($0) }

        backend.updateExternalPlayback(true)

        #expect(backend.isExternalPlaybackActive == true)
        #expect(received == [true])
        backend.dispose()
    }

    @Test("重复上报同一个值不回调")
    func ignoresDuplicateValue() {
        let backend = AVPlayerBackend()
        var received: [Bool] = []
        backend.onExternalPlaybackChange = { received.append($0) }

        backend.updateExternalPlayback(true)
        backend.updateExternalPlayback(true)
        backend.updateExternalPlayback(false)
        backend.updateExternalPlayback(false)

        #expect(received == [true, false])
        backend.dispose()
    }

    @Test("dispose 之后不再持有回调")
    func clearsCallbackOnDispose() {
        let backend = AVPlayerBackend()
        var received: [Bool] = []
        backend.onExternalPlaybackChange = { received.append($0) }

        backend.dispose()
        backend.updateExternalPlayback(true)

        #expect(received.isEmpty)
    }
}
