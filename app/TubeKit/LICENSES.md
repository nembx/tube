# Third-Party Licenses

CezzuKit 引入的第三方组件清单与各自的 license 信息。

## Swift 包依赖

### Kanna (5.3.0+)

- **用途**：唯一第三方 Swift 包依赖；libxml2 的 Swift 包装，提供 HTML 解析与
  XPath 1.0 求值，支撑整个 `CezzuRule` 引擎。
- **仓库**：https://github.com/tid-kijyun/Kanna
- **License**：MIT License
- **版权**：Copyright (c) 2014 Atsushi Kiwaki

完整 license 文本见 Kanna 仓库 / SwiftPM checkouts 目录下 `LICENSE` 文件。

## 规则格式

cezzu-rule 是 Cezzu 自己的 JSON 规则格式。完整字段定义见 `cezzu-rule/docs/rule-format.md`。

## 系统框架

以下系统框架不在第三方 license 之列，但 v1 重度依赖：

- SwiftUI（含 Liquid Glass APIs `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `glassEffectID`）
- AVFoundation / AVKit（AVPlayer, AVURLAsset, AVPictureInPictureController）
- WebKit（WKWebView, WKContentRuleList, WKScriptMessageHandler, WKHTTPCookieStore）
- SwiftData（@Model, ModelContainer, FetchDescriptor）
- Network.framework（NWListener, NWConnection, NWParameters）
- Foundation（URLSession, JSONDecoder, FileManager, …）
