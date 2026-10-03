import Testing
@testable import CezzuKit

@Suite("PlayerChromeController")
@MainActor
struct PlayerChromeControllerTests {

    @Test("default controller is a safe no-op")
    func defaultIsNoop() {
        let controller = PlayerChromeController()
        // 不应该 crash — 默认构造给 CompactRootView 这种没 sidebar 的场景兜底
        controller.setSidebarHidden(true)
        controller.setSidebarHidden(false)
    }

    @Test("custom closure receives the last hidden value")
    func customClosureInvoked() {
        var received: [Bool] = []
        let controller = PlayerChromeController { hidden in
            received.append(hidden)
        }

        controller.setSidebarHidden(true)
        controller.setSidebarHidden(false)
        controller.setSidebarHidden(true)

        #expect(received == [true, false, true])
    }
}
