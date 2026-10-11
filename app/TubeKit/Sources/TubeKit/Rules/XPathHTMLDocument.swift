import Foundation

/// 抽象的 XPath HTML 节点 —— 把 Kanna 的细节藏在协议后面，方便测试 / 替换。
public protocol XPathHTMLNode: Sendable {
    /// 节点的文本内容（已做基础 trim）。
    var text: String? { get }

    /// 取属性 —— `node["href"]` 等。
    subscript(name: String) -> String? { get }

    /// 在当前节点的子树里求 XPath。
    func xpath(_ expression: String) -> [XPathHTMLNode]
}

/// 抽象的 XPath HTML 文档。
public protocol XPathHTMLDocument: Sendable {
    /// 在整个文档上求 XPath。
    func xpath(_ expression: String) -> [XPathHTMLNode]
}

/// 工厂闭包：给定一段 HTML 字符串，构造 `XPathHTMLDocument`。
/// 把 Kanna 的依赖装进闭包里，方便测试时替换。
public typealias XPathDocumentFactory = @Sendable (String) throws -> any XPathHTMLDocument
