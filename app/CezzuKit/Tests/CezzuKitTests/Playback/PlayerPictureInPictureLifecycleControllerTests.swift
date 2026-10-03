import Testing
@testable import CezzuKit

@Suite("PlayerPictureInPictureLifecycleController")
@MainActor
struct PlayerPictureInPictureLifecycleControllerTests {

    @Test("default controller is a safe no-op")
    func defaultIsNoop() {
        let controller = PlayerPictureInPictureLifecycleController()
        controller.didStartPictureInPicture()

        var restored: Bool?
        controller.restoreUserInterface { success in
            restored = success
        }

        #expect(restored == true)
    }

    @Test("custom closures receive lifecycle callbacks")
    func customClosuresInvoked() {
        var didStartCount = 0
        var restored: [Bool] = []
        let controller = PlayerPictureInPictureLifecycleController(
            didStartPictureInPicture: {
                didStartCount += 1
            },
            restoreUserInterface: { completion in
                restored.append(true)
                completion(false)
            }
        )

        controller.didStartPictureInPicture()
        controller.didStartPictureInPicture()

        var completionResults: [Bool] = []
        controller.restoreUserInterface { success in
            completionResults.append(success)
        }

        #expect(didStartCount == 2)
        #expect(restored == [true])
        #expect(completionResults == [false])
    }
}
