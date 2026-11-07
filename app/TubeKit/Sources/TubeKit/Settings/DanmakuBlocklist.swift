import Foundation

/// 按包含关系屏蔽弹幕。词条逐行保存，匹配忽略大小写和全角 / 半角差异。
public struct DanmakuBlocklist: Sendable {
    public static let storageKey = "tube.playback.danmakuBlockedKeywords"

    public let keywords: [String]
    private let normalizedKeywords: [String]

    public init(rawValue: String) {
        var seen: Set<String> = []
        let keywords = rawValue.components(separatedBy: .newlines).compactMap { line -> String? in
            let keyword = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty, seen.insert(Self.normalize(keyword)).inserted else { return nil }
            return keyword
        }
        self.keywords = keywords
        self.normalizedKeywords = keywords.map(Self.normalize)
    }

    public var rawValue: String { keywords.joined(separator: "\n") }

    public func blocks(_ text: String) -> Bool {
        guard !normalizedKeywords.isEmpty else { return false }
        let normalizedText = Self.normalize(text)
        return normalizedKeywords.contains { normalizedText.contains($0) }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
