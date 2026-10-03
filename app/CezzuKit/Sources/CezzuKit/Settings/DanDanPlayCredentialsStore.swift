import Foundation

/// 用户在设置里填的 DanDanPlay 凭证。开启 `useCustom` 时优先使用；关闭时回落到
/// Info.plist / 环境变量里的内置凭证。
public enum DanDanPlayCredentialsStore {
    public static let useCustomKey = "cezzu.dandanplay.useCustomCredentials"
    public static let appIDKey = "cezzu.dandanplay.customAppID"
    public static let appSecretKey = "cezzu.dandanplay.customAppSecret"

    public static let useCustomDefault = false

    public struct Snapshot: Sendable {
        public let useCustom: Bool
        public let appID: String
        public let appSecret: String

        public init(useCustom: Bool, appID: String, appSecret: String) {
            self.useCustom = useCustom
            self.appID = appID
            self.appSecret = appSecret
        }

        public var resolvedPair: (appID: String, appSecret: String)? {
            guard useCustom else { return nil }
            let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !secret.isEmpty else { return nil }
            return (id, secret)
        }
    }

    public static func snapshot(from defaults: UserDefaults = .standard) -> Snapshot {
        Snapshot(
            useCustom: defaults.object(forKey: useCustomKey) as? Bool ?? useCustomDefault,
            appID: defaults.string(forKey: appIDKey) ?? "",
            appSecret: defaults.string(forKey: appSecretKey) ?? ""
        )
    }
}
