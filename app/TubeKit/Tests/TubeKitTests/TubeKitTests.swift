import Testing
@testable import TubeKit

@Suite("TubeKit smoke")
struct TubeKitSmokeTests {
    @Test("version is non-empty")
    func versionIsNonEmpty() {
        #expect(!TubeKit.version.isEmpty)
    }
}
