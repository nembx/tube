import Testing
@testable import TubeKit

@Suite("PlayerPresentationController")
@MainActor
struct PlayerPresentationControllerTests {

    @Test("default controller is a safe no-op")
    func defaultIsNoop() {
        let controller = PlayerPresentationController()
        #expect(!controller.prefersDedicatedWindow)
        // 默认宿主没有「旋转」这回事，播放页据此不显示那个按钮。
        #expect(!controller.supportsOrientationToggle)
        controller.enterPlayback()
        controller.setPlaybackLandscape(true)
        controller.restoreDefaultPlaybackPresentation()
        controller.setSystemFullscreen(true)
        controller.setSystemFullscreen(false)
    }

    @Test("custom closures receive presentation callbacks")
    func customClosuresInvoked() {
        var enterRequests = 0
        var landscapeValues: [Bool] = []
        var restoreRequests = 0
        var fullscreenValues: [Bool] = []
        let controller = PlayerPresentationController(
            enterPlayback: {
                enterRequests += 1
            },
            setPlaybackLandscape: { landscape in
                landscapeValues.append(landscape)
            },
            restoreDefaultPlaybackPresentation: {
                restoreRequests += 1
            },
            setSystemFullscreen: { fullscreen in
                fullscreenValues.append(fullscreen)
            },
            supportsOrientationToggle: true
        )

        controller.enterPlayback()
        controller.setPlaybackLandscape(true)
        controller.setPlaybackLandscape(false)
        controller.restoreDefaultPlaybackPresentation()
        controller.setSystemFullscreen(true)
        controller.setSystemFullscreen(false)

        #expect(enterRequests == 1)
        #expect(landscapeValues == [true, false])
        #expect(restoreRequests == 1)
        #expect(fullscreenValues == [true, false])
        #expect(controller.supportsOrientationToggle)
    }

    @Test("a dedicated window is opt-in")
    func dedicatedWindowMode() {
        #expect(PlayerPresentationController(prefersDedicatedWindow: true).prefersDedicatedWindow)
    }
}
