import Testing
@testable import CezzuKit

@Suite("PlayerInteractionController")
@MainActor
struct PlayerInteractionControllerTests {

    @Test("default controller keeps fullscreen toggle")
    func defaultValues() {
        let controller = PlayerInteractionController()

        #expect(controller.showsFullscreenToggle)
    }

    @Test("custom controller exposes configured toggle capabilities")
    func customValues() {
        let controller = PlayerInteractionController(showsFullscreenToggle: false)

        #expect(!controller.showsFullscreenToggle)
    }
}
