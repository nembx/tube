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
        let xpath = document.xpath(expression)
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
        node.xpath(expression).compactMap { (n: Kanna.XMLElement) -> XPathHTMLNode? in
            KannaXPathNode(node: n)
        }
    }
}
