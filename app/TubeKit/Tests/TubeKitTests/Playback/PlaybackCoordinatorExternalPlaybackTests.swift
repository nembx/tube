import Foundation
import Testing

@testable import TubeKit

@Suite("PlaybackCoordinator 投屏地址切换")
@MainActor
struct PlaybackCoordinatorExternalPlaybackTests {

    @Test("没走反代的线路，投屏切换什么都不做")
    func ignoresWhenNotProxied() async {
        let coordinator = PlaybackCoordinator()

        await coordinator.applyExternalPlayback(true)

        #expect(coordinator.currentMediaURL == nil)
        #expect(coordinator.externalPlaybackUnavailable == false)
    }

    @Test("退出投屏同样不动没走反代的线路")
    func ignoresDeactivationWhenNotProxied() async {
        let coordinator = PlaybackCoordinator()

        await coordinator.applyExternalPlayback(false)

        #expect(coordinator.currentMediaURL == nil)
        #expect(coordinator.externalPlaybackUnavailable == false)
    }

    @Test("backend 的投屏回调接到了协调层上")
    func backendCallbackIsWired() {
        let backend = AVPlayerBackend()
        _ = PlaybackCoordinator(backend: backend)

        #expect(backend.onExternalPlaybackChange != nil)
    }
}
