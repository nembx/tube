import Foundation

/// 把 Bangumi 条目名和站点搜索结果标题对上号。
///
/// 站点标题的季号写法千奇百怪（「第三季」「III」「S3」「3rd Season」），而错配的代价很高：
/// 详情页显示第三季、播出来是第一季，用户看不出任何异常。所以先把季号从标题里摘出来单独比，
/// 季度不一致直接判 0 分，不允许「包含关系」把上一季当成兜底答案。
enum TitleMatcher {

    /// 标题里标注的季度。没有任何季度标记时按第一季处理 —— 绝大多数站点的第一季不写季号。
    static func season(of title: String) -> Int {
        let text = title.lowercased()
        for marker in seasonMarkers {
            guard let captured = firstMatch(in: text, pattern: marker.pattern) else { continue }
            return marker.value(captured) ?? 1
        }
        return 1
    }

    /// 摘掉季号、保留原有大小写与词间空格。用来当搜索关键词（站点搜索吃原文，不吃归一化后的串）。
    static func strippingSeason(_ title: String) -> String {
        var text = title
        for marker in seasonMarkers {
            text = replacingMatches(in: text, pattern: marker.pattern, with: " ")
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉季号后的基名，用来跨写法比对（「药屋少女的呢喃 第三季」与「药屋少女的呢喃Ⅲ」同基名）。
    static func baseName(of title: String) -> String {
        normalize(strippingSeason(title))
    }

    /// 拿去喂站点搜索的关键词表，按可信度排序、去重、限量。
    ///
    /// 站点对同一部番的收录名千奇百怪（「药师少女的独语」「Kusuriya no Hitorigoto」），
    /// Bangumi infobox 里的别名正好覆盖这些写法；去季号的基名则救那些搜索不认季号后缀的站点。
    ///
    /// 关键词会和每条规则做笛卡尔积并发请求，所以要限量；但限的是**总请求数**而不是并发度——
    /// 每条规则是一个独立域名，URLSession 本身按 host 排队（每 host 4~6 条连接），
    /// 多一个关键词只是给每个站点多排一次队，不会互相抢带宽。
    static func searchKeywords(
        displayName: String,
        name: String,
        aliases: [String],
        limit: Int = 8
    ) -> [String] {
        var candidates = [displayName, name]
        candidates.append(strippingSeason(displayName))
        candidates.append(contentsOf: aliases)

        var seen: Set<String> = []
        var keywords: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            keywords.append(trimmed)
            if keywords.count == limit { break }
        }
        return keywords
    }

    /// 把 Bangumi infobox 的「别名」值拆成一条条别名。解码器把数组型 value 用「、」拼过，
    /// 站点侧手写的别名则常用 `/` 分隔。
    static func splitAliases(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: "、/／"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 条目本身是第几季。季度是条目的属性，不是关键词的属性 —— 关键词里既有去了季号的基名，
    /// 也有 infobox 里普遍不带季号的别名，拿它们各自的季号去比会把季度门禁整个绕过去。
    static func expectedSeason(displayName: String, name: String) -> Int {
        for candidate in [displayName, name] {
            let value = season(of: candidate)
            if value > 1 { return value }
        }
        return 1
    }

    /// 标题与关键字的重合度。0 表示不匹配，调用方必须丢弃。只看名字，不管季度。
    ///
    /// 比较走掩码等价（见 `maskCharacters`）：没有掩码时和普通的 `==` / `contains`
    /// 完全一致，有掩码时掩码顶一个字。
    static func score(title: String, keyword: String) -> Int {
        let titleBase = Array(baseName(of: title))
        let keywordBase = Array(baseName(of: keyword))
        guard !titleBase.isEmpty, !keywordBase.isEmpty else { return 0 }

        if maskedEquals(titleBase, keywordBase) { return 3 }
        if maskedContains(titleBase, keywordBase) { return 2 }
        if maskedContains(keywordBase, titleBase) { return 1 }
        return 0
    }

    /// Bangumi 会把标题里的敏感字打码，资源站用的是原字（「…她的〇穴」对「…她的小穴」）。
    /// 差这一个字，纯包含匹配就判 0 分，条目搜得到却一个播放源都没有。
    ///
    /// 掩码只顶**一个**字，不是通配一整段 —— 放宽成任意长度会让不同的番互相错配，
    /// 而错配的代价在这里很高（详情页显示 A、播出来是 B，用户看不出异常）。
    private static let maskCharacters: Set<Character> = ["〇", "○", "◯", "●", "×", "✕", "✖", "＊", "*"]

    /// 掩码顶替的字数上限（占比）。全是掩码的标题能匹配任何同长度的串，
    /// 必须要求两边还剩下足够多真字做锚点。
    private static let maxMaskedRatio = 0.25

    /// 逐字比较，任一侧的掩码匹配对面任意一个字。无掩码时等价于 `==`。
    private static func maskedEquals(
        _ lhs: ArraySlice<Character>, _ rhs: ArraySlice<Character>
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var substitutions = 0
        for (l, r) in zip(lhs, rhs) where l != r {
            guard maskCharacters.contains(l) || maskCharacters.contains(r) else { return false }
            substitutions += 1
        }
        guard substitutions > 0 else { return true }
        return Double(substitutions) <= Double(lhs.count) * maxMaskedRatio
    }

    private static func maskedEquals(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        maskedEquals(lhs[...], rhs[...])
    }

    /// `haystack` 里是否存在一段与 `needle` 掩码等价的连续字符。无掩码时等价于 `contains`。
    private static func maskedContains(_ haystack: [Character], _ needle: [Character]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if maskedEquals(haystack[start..<(start + needle.count)], needle[...]) {
                return true
            }
        }
        return false
    }

    /// 一条带匹配分的候选结果。
    struct ScoredResult: Hashable, Sendable {
        let result: SearchResult
        /// 标题重合度 1...3。
        let score: Int
        /// 站点标题标注的季度。
        let season: Int
        /// 季度是否和条目一致。不一致的照样进列表，只是排在后面且不会被自动选中。
        let seasonMatches: Bool

        /// 排序键：先看季度对不对，再看名字有多贴。
        static func isOrderedBefore(_ lhs: ScoredResult, _ rhs: ScoredResult) -> Bool {
            if lhs.seasonMatches != rhs.seasonMatches { return lhs.seasonMatches }
            return lhs.score > rhs.score
        }
    }

    /// 一批结果里所有匹配得上的候选。同一个详情页只保留最高分的那次。
    ///
    /// 站点上同一部番常有多条收录（不同版本 / 不同入口），全都留下来交给用户挑，
    /// 只丢名字真正对不上的（0 分）。季度对不上的**不丢**——站点把续作挂在同一个入口下
    /// 是常态，丢掉会让列表凭空变短；改成排在后面并标注，自动选源不会碰它们。
    static func matches(
        in results: [SearchResult],
        keywords: [String],
        expectedSeason: Int
    ) -> [ScoredResult] {
        var bestByURL: [URL: ScoredResult] = [:]
        for keyword in keywords {
            for result in results {
                let value = score(title: result.title, keyword: keyword)
                guard value > 0 else { continue }
                if let existing = bestByURL[result.detailURL], existing.score >= value { continue }
                let titleSeason = season(of: result.title)
                bestByURL[result.detailURL] = ScoredResult(
                    result: result,
                    score: value,
                    season: titleSeason,
                    seasonMatches: titleSeason == expectedSeason
                )
            }
        }
        return bestByURL.values.sorted(by: ScoredResult.isOrderedBefore)
    }

    /// 在一批结果里挑最靠谱的一个。全都对不上名字时返回 nil。
    static func bestMatch(
        in results: [SearchResult],
        keywords: [String],
        expectedSeason: Int
    ) -> ScoredResult? {
        matches(in: results, keywords: keywords, expectedSeason: expectedSeason).first
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - internals

    private struct SeasonMarker: Sendable {
        let pattern: String
        let value: @Sendable (String) -> Int?
    }

    /// 顺序即优先级：先中日文季号，再英文，最后罗马数字（最容易误伤，放最后）。
    private static let seasonMarkers: [SeasonMarker] = [
        SeasonMarker(pattern: "第\\s*([0-9]+|[一二三四五六七八九十]+)\\s*[季期]", value: parseNumber),
        SeasonMarker(pattern: "season\\s*([0-9]+)", value: parseNumber),
        SeasonMarker(pattern: "([0-9]+)\\s*(?:st|nd|rd|th)\\s*season", value: parseNumber),
        SeasonMarker(pattern: "(?<![a-z0-9])s\\s*([0-9]+)(?![a-z0-9])", value: parseNumber),
        SeasonMarker(
            // 只认 II/III/IV：单独一个 "V" 在标题里更可能是别的意思，误伤成本太高。
            pattern: "(?<![a-z])(ⅱ|ⅲ|ⅳ|ii|iii|iv)(?![a-z])",
            value: { romanValues[$0] }
        ),
    ]

    private static let romanValues: [String: Int] = [
        "ii": 2, "iii": 3, "iv": 4,
        "ⅱ": 2, "ⅲ": 3, "ⅳ": 4,
    ]

    private static let chineseDigits: [Character: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9, "十": 10,
    ]

    private static func parseNumber(_ value: String) -> Int? {
        if let arabic = Int(value) { return arabic }
        // 站点季号极少超过十几季，"十二" 这种两位写法按 十+个位 处理就够。
        var total = 0
        var sawTen = false
        for char in value {
            guard let digit = chineseDigits[char] else { return nil }
            if digit == 10 {
                total = total == 0 ? 10 : total * 10
                sawTen = true
            } else {
                total = sawTen ? total + digit : digit
            }
        }
        return total == 0 ? nil : total
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }

    /// 抹掉季号整段。所有 pattern 的定界都走零宽断言，匹配范围里只有季号本身，
    /// 不会连标题的字一起削掉。
    private static func replacingMatches(
        in text: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let regex = regex(pattern) else { return text }
        let ranges = regex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
        guard !ranges.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for range in ranges {
            result += text[cursor..<range.lowerBound]
            result += replacement
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
