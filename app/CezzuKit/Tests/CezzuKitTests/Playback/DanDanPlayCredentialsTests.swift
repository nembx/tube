import Foundation
import Testing
@testable import CezzuKit

@Suite("DanDanPlayCredentials")
struct DanDanPlayCredentialsTests {
    @Test("prefers Info.plist values over environment")
    func prefersBundleValues() {
        let bundle = MockBundle(
            values: [
                "DanDanPlayAppID": "bundle-id",
                "DanDanPlayAppSecret": "bundle-secret",
            ]
        )

        let credentials = DanDanPlayCredentials(
            bundle: bundle,
            environment: [
                "DANDANPLAY_APP_ID": "env-id",
                "DANDANPLAY_APP_SECRET": "env-secret",
            ]
        )

        #expect(credentials?.appID == "bundle-id")
        #expect(credentials?.appSecret == "bundle-secret")
    }

    @Test("falls back to environment variables")
    func fallsBackToEnvironment() {
        let credentials = DanDanPlayCredentials(
            bundle: MockBundle(values: [:]),
            environment: [
                "DANDANPLAY_APP_ID": "env-id",
                "DANDANPLAY_APP_SECRET": "env-secret",
            ]
        )

        #expect(credentials?.appID == "env-id")
        #expect(credentials?.appSecret == "env-secret")
    }

    @Test("returns nil when credentials are missing")
    func returnsNilWhenMissing() {
        let credentials = DanDanPlayCredentials(
            bundle: MockBundle(values: [:]),
            environment: [:]
        )

        #expect(credentials == nil)
    }
}

private final class MockBundle: Bundle, @unchecked Sendable {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func object(forInfoDictionaryKey key: String) -> Any? {
        values[key]
    }
}
