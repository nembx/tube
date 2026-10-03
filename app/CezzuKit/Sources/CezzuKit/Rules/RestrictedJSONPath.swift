import Foundation

/// 受限 JSONPath 求值器（对齐 Kazumi `RestrictedJsonPath`）。
///
/// 仅支持：
/// - `$` 根
/// - `.field` / `['field']` / `["field"]`
/// - `[index]` / `[*]`
///
/// 不支持：`..` 递归、`?()` 过滤、切片、函数调用。
public enum RestrictedJSONPath: Sendable {
    public struct FormatError: Error, Sendable, CustomStringConvertible {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    public static func validate(_ expression: String) throws {
        guard !expression.isEmpty, expression.hasPrefix("$") else {
            throw FormatError("JSONPath 必须以 $ 开头: \(expression)")
        }
        var index = expression.index(after: expression.startIndex)
        while index < expression.endIndex {
            let char = expression[index]
            if char == "." {
                expression.formIndex(after: &index)
                let start = index
                while index < expression.endIndex {
                    let c = expression[index]
                    if c.isLetter || c.isNumber || c == "_" || c == "$" || c == "-" {
                        expression.formIndex(after: &index)
                    } else {
                        break
                    }
                }
                if index == start {
                    throw FormatError("不支持的 JSONPath: \(expression)")
                }
                continue
            }
            if char == "[" {
                let end = try findBracketEnd(expression, start: index)
                let content = expression[expression.index(after: index)..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isIndex = content.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
                let isWildcard = content == "*"
                let isQuoted =
                    (content.hasPrefix("'") && content.hasSuffix("'") && content.count >= 2)
                    || (content.hasPrefix("\"") && content.hasSuffix("\"") && content.count >= 2)
                if !isIndex && !isWildcard && !isQuoted {
                    throw FormatError("不支持的 JSONPath 片段: [\(content)]")
                }
                index = expression.index(after: end)
                continue
            }
            throw FormatError("不支持的 JSONPath: \(expression)")
        }
    }

    public static func read(_ document: Any, expression: String) throws -> [Any] {
        try validate(expression)
        // `$` alone
        if expression == "$" { return [document] }
        var nodes: [Any] = [document]
        var index = expression.index(after: expression.startIndex)
        while index < expression.endIndex {
            let char = expression[index]
            if char == "." {
                expression.formIndex(after: &index)
                let start = index
                while index < expression.endIndex {
                    let c = expression[index]
                    if c.isLetter || c.isNumber || c == "_" || c == "$" || c == "-" {
                        expression.formIndex(after: &index)
                    } else {
                        break
                    }
                }
                let field = String(expression[start..<index])
                nodes = try nodes.flatMap { try readField($0, field: field) }
                continue
            }
            if char == "[" {
                let end = try findBracketEnd(expression, start: index)
                let content = expression[expression.index(after: index)..<end]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if content == "*" {
                    nodes = try nodes.flatMap { try readWildcard($0) }
                } else if content.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
                    let idx = Int(content)
                {
                    nodes = try nodes.flatMap { try readIndex($0, index: idx) }
                } else if (content.hasPrefix("'") && content.hasSuffix("'"))
                    || (content.hasPrefix("\"") && content.hasSuffix("\""))
                {
                    let field = String(content.dropFirst().dropLast())
                    nodes = try nodes.flatMap { try readField($0, field: field) }
                } else {
                    throw FormatError("不支持的 JSONPath 片段: [\(content)]")
                }
                index = expression.index(after: end)
                continue
            }
            throw FormatError("不支持的 JSONPath: \(expression)")
        }
        return nodes
    }

    public static func readFirst(_ document: Any, expression: String) throws -> Any? {
        try read(document, expression: expression).first
    }

    // MARK: - internals

    private static func findBracketEnd(_ expression: String, start: String.Index) throws
        -> String.Index
    {
        var quote: Character?
        var escaped = false
        var i = expression.index(after: start)
        while i < expression.endIndex {
            let char = expression[i]
            if escaped {
                escaped = false
                expression.formIndex(after: &i)
                continue
            }
            if char == "\\" {
                escaped = true
                expression.formIndex(after: &i)
                continue
            }
            if let q = quote {
                if char == q { quote = nil }
                expression.formIndex(after: &i)
                continue
            }
            if char == "'" || char == "\"" {
                quote = char
                expression.formIndex(after: &i)
                continue
            }
            if char == "]" { return i }
            expression.formIndex(after: &i)
        }
        throw FormatError("JSONPath 缺少 ]: \(expression)")
    }

    private static func asDict(_ value: Any) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in d {
                if let ks = k as? String { out[ks] = v }
            }
            return out
        }
        return nil
    }

    private static func asArray(_ value: Any) -> [Any]? {
        if let a = value as? [Any] { return a }
        if let a = value as? NSArray { return a.map { $0 as Any } }
        return nil
    }

    private static func readField(_ value: Any, field: String) throws -> [Any] {
        guard let dict = asDict(value), let child = dict[field] else { return [] }
        return [child]
    }

    private static func readIndex(_ value: Any, index: Int) throws -> [Any] {
        guard let arr = asArray(value), index >= 0, index < arr.count else { return [] }
        return [arr[index]]
    }

    private static func readWildcard(_ value: Any) throws -> [Any] {
        if let arr = asArray(value) { return arr }
        if let dict = asDict(value) { return Array(dict.values) }
        return []
    }
}
