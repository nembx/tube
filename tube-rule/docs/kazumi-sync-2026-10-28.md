# KazumiRules 同步记录（2026-10-28）

上游快照：[4f93eec10acabfeeaa2b687857b03d0766977d0f](https://github.com/Predidit/KazumiRules/tree/4f93eec10acabfeeaa2b687857b03d0766977d0f)。规则文件沿用上游内容，MIT 原作者版权声明保留于 `tube-rule/LICENSE`。

## 数据源变更

| 规则 | 原状态 | 本次状态 |
| --- | --- | --- |
| LMM | 2.1，弃用 | 2.3，启用；API 搜索 + XPath 章节 |
| TvTFun | 1.1，弃用 | 1.3，启用；API 搜索 + XPath 章节 |
| xfdmnext | 1.0，弃用 | 1.1，启用；更新 API 地址及请求配置，解析全部线路 |
| MXdm | 2.3 | 2.4，更新 XPath |
| dalvdm | 1.0 | 1.2，更新域名，改为 API 搜索 |
| giriGiriLove | 2.4 | 2.6，API 搜索及分隔格式章节 |
| mgnacg | 1.0 | 1.2，API 搜索 + XPath 章节 |
| moonci | 1.0 | 1.1，API 搜索 + XPath 章节 |
| mutefun | 1.2 | 1.5，更新域名，API 搜索 + XPath 章节 |
| gugu3 | 1.3，启用 | 跟随上游弃用，文件保留 |

保留 Tube 独立修复的 `yinghua 1.3`，未覆盖为上游弃用的 `iyinghua.com` 规则。85 个规则文件中，启用条目从 17 增至 19，弃用条目从 68 减至 66。App 升级时通过现有种子对账流程补齐新源、更新版本、移除弃用官方源，并保留启用开关。

## 兼容性修正

- 解码并持久化 `searchApiConfig.sourceTemplate`，按 Kazumi 语义替换 URL 编码后的 `@source`，包括 `/GV@source` 写法。
- API 搜索接 XPath 章节时，将来源 id / 相对路径基于 `baseURL` 解析为 HTTP(S) 详情 URL；API 章节继续保留 source id。
- 将 Kazumi 的 `[@class*='value']` 转换为 libxml2 支持的 `contains()`，文档和相对节点查询均适用，不改写字符串字面量。
- JSON 请求体保留数字、布尔值、null、数组和嵌套对象，在字符串值上替换模板并正确转义关键字。
- 历史 `captchaType = 3` / `captchaScript` 以及额外验证码检测方式仍不支持，不能宣称任意 Kazumi 规则完全兼容；此上游有效规则集不依赖这些能力。

## 验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path app/TubeKit`：822 tests / 127 suites 通过；仓库已有的 SwiftData CLI 跳过项保持原状。
- 规则相关回归：35 tests / 6 suites 通过，覆盖三个新源搜索到剧集的完整请求与解析流程、混合 API/XPath URL 映射、模板编码、请求体类型、种子迁移和索引一致性。
- 在线搜索关键字：`鬼灭`。抓取真实响应后，使用 Tube 的 `ApiRuleEngine` / `LiveRuleEngine` 检查：

| 规则 | 搜索结果数 | 第一条结果的线路数 | 总剧集入口数 |
| --- | --- | --- | --- |
| LMM | 12 | 3 | 4 |
| TvTFun | 9 | 1 | 1 |
| xfdmnext | 6 | 1 | 1 |

另确认 moonci、mgnacg、giriGiriLove 的搜索响应能返回 JSON 结果。dalvdm 在当前网络返回 HTTP 403；mutefun 返回 HTTP 200，但内容是 PNG 图片而非搜索 JSON，两者未确认在线可用，更新的是上游现有规则配置。

以上验证截至搜索、详情和剧集入口解析，未完成所有站点的 WebView 视频嗅探及实际起播测试。线上状态可能随站点变化。
