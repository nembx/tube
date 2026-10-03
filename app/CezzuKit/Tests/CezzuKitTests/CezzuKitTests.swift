import Testing
@testable import CezzuKit

@Suite("CezzuKit smoke")
struct CezzuKitSmokeTests {
    @Test("version is non-empty")
    func versionIsNonEmpty() {
        #expect(!CezzuKit.version.isEmpty)
    }
}
