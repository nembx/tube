import Foundation

/// Bangumi 条目上的一个 tag。`count` = 投这个 tag 的人数。
public struct BangumiTag: Hashable, Sendable, Codable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case count
    }
}
