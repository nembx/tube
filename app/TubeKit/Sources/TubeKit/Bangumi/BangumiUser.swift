import Foundation

/// 已登录的 Bangumi 用户。`GET /v0/me` 的返回体。
public struct BangumiUser: Hashable, Sendable, Identifiable, Codable {
    public let id: Int
    public let username: String
    public let nickname: String
    public let avatarLarge: String
    public let avatarMedium: String
    public let avatarSmall: String
    public let sign: String

    public init(
        id: Int,
        username: String,
        nickname: String,
        avatarLarge: String = "",
        avatarMedium: String = "",
        avatarSmall: String = "",
        sign: String = ""
    ) {
        self.id = id
        self.username = username
        self.nickname = nickname
        self.avatarLarge = avatarLarge
        self.avatarMedium = avatarMedium
        self.avatarSmall = avatarSmall
        self.sign = sign
    }

    /// 展示名：昵称优先，回落用户名。
    public var displayName: String {
        nickname.isEmpty ? username : nickname
    }

    /// 头像优先用中等尺寸，回落其它。
    public var avatarURL: URL? {
        let raw = [avatarMedium, avatarLarge, avatarSmall].first { !$0.isEmpty } ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        return URL(string: raw)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case nickname
        case avatar
        case sign
    }

    private struct Avatar: Decodable {
        let large: String?
        let medium: String?
        let small: String?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.username = (try? c.decode(String.self, forKey: .username)) ?? ""
        let rawNick = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        self.nickname = rawNick.isEmpty ? self.username : rawNick
        let avatar = try? c.decode(Avatar.self, forKey: .avatar)
        self.avatarLarge = avatar?.large ?? ""
        self.avatarMedium = avatar?.medium ?? ""
        self.avatarSmall = avatar?.small ?? ""
        self.sign = (try? c.decode(String.self, forKey: .sign)) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encode(nickname, forKey: .nickname)
        try c.encode(sign, forKey: .sign)
        var a = c.nestedContainer(keyedBy: AvatarKeys.self, forKey: .avatar)
        try a.encode(avatarLarge, forKey: .large)
        try a.encode(avatarMedium, forKey: .medium)
        try a.encode(avatarSmall, forKey: .small)
    }

    private enum AvatarKeys: String, CodingKey {
        case large, medium, small
    }
}
