import Foundation
@preconcurrency import Kanna

/// `XPathHTMLDocument` 的生产实现 —— 基于 [Kanna](https://github.com/tid-kijyun/Kanna)（libxml2）。
///
/// 标记 `@unchecked Sendable`：Kanna 的 `HTMLDocument` / `XMLElement` 不是 Sendable，
/// 但我们的使用模式是"在单个异步调用栈内构造 + 求值 + 销毁"，不会跨 actor 传递引用。
public final class KannaXPathHTMLDocument: XPathHTMLDocument, @unchecked Sendable {
    private let document: HTMLDocument

    public init(html: String) throws {
        do {
            self.document = try Kanna.HTML(html: html, encoding: .utf8)
        } catch {
            throw RuleEngineError.parse(message: "Kanna.HTML failed: \(error)", rule: "?")
        }
    }

    public func xpath(_ expression: String) -> [XPathHTMLNode] {
        let xpath = document.xpath(KazumiXPath.normalize(expression))
        return xpath.compactMap { node -> XPathHTMLNode? in
            KannaXPathNode(node: node)
        }
    }

    /// 默认的工厂闭包 —— 注入到 `LiveRuleEngine` 用。
    public static let factory: XPathDocumentFactory = { html in
        try KannaXPathHTMLDocument(html: html)
    }
}

/// Kanna 节点的 `XPathHTMLNode` 包装。
final class KannaXPathNode: XPathHTMLNode, @unchecked Sendable {
    let node: any Kanna.XMLElement

    init(node: any Kanna.XMLElement) {
        self.node = node
    }

    var text: String? {
        node.text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    subscript(name: String) -> String? {
        node[name]
    }

    func xpath(_ expression: String) -> [XPathHTMLNode] {
        node.xpath(KazumiXPath.normalize(expression)).compactMap { (n: Kanna.XMLElement) -> XPathHTMLNode? in
            KannaXPathNode(node: n)
        }
    }
}

/// Kazumi 的 XPath 库支持 CSS 风格的属性子串比较，libxml2 需要 contains()。
private enum KazumiXPath {
    // 先匹配完整字符串字面量，避免改写引号内碰巧出现的 @attr*= 文本。
    private static let attributeContains = try! NSRegularExpression(
        pattern: #"'[^']*'|"[^"]*"|@([A-Za-z_][A-Za-z0-9_.:-]*)\s*\*=\s*('[^']*'|"[^"]*")"#
    )

    static func normalize(_ expression: String) -> String {
        let text = expression as NSString
        let matches = attributeContains.matches(
            in: expression, range: NSRange(location: 0, length: text.length)
        )
        var result = expression
        for match in matches.reversed() where match.range(at: 1).location != NSNotFound {
            guard let range = Range(match.range, in: result) else { continue }
            let attribute = text.substring(with: match.range(at: 1))
            let value = text.substring(with: match.range(at: 2))
            result.replaceSubrange(range, with: "contains(@\(attribute), \(value))")
        }
        return result
    }
}
