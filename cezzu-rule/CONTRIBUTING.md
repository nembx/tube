# 贡献指南

感谢对 cezzu-rule 的贡献兴趣。本文档描述如何添加 / 更新 / 弃用一条资源站规则。

## 添加新规则（4 步）

### 1. 写规则 JSON

在 `rules/` 下新建 `<name>.json`。**文件名必须与 JSON 内的 `name` 字段一致**（不含 `.json` 后缀）。

字段定义见 [`docs/rule-format.md`](./docs/rule-format.md) —— 这是协议的唯一权威文档，请通读。

最小的合法规则示例：

```json
{
    "api": "1",
    "type": "anime",
    "name": "myRule",
    "version": "1.0",
    "muliSources": true,
    "useWebview": true,
    "useNativePlayer": true,
    "userAgent": "",
    "baseURL": "https://example.com/",
    "searchURL": "https://example.com/search?q=@keyword",
    "searchList": "//div[@class='result']",
    "searchName": "//a/h3",
    "searchResult": "//a",
    "chapterRoads": "//ul[@class='episodes']",
    "chapterResult": "//li/a"
}
```

### 2. 本地测试

把 `rules/<name>.json` 直接拖进 Cezzu App 的"已安装规则 → 导入"入口，然后：

- 在搜索页输入一个常见番剧名（例如「孤独摇滚」「鬼灭之刃」），确认能看到结果列表
- 点进任一结果，确认能看到剧集列表（如果 `muliSources = true`，确认能看到多条线路）
- 点任一集，确认 WKWebView 能嗅探出可播放 URL 并起播

如果任意一步失败，先用 Safari Web Inspector 看实际站点 DOM 结构，调整 XPath 表达式。

### 3. 重新生成索引

```bash
./scripts/update_index.swift
```

这会扫描 `rules/*.json`，更新 `index.json`。**每次改了 `rules/` 下任何文件都必须跑这一步**，否则线上 App 看不到改动。

### 4. 提 PR

PR 描述里写上：
- 新增 / 修改的站点名
- 至少一个本地测试通过的搜索 keyword
- 截图（可选但鼓励）

## 弃用规则

某站点彻底失效或政策不允许时：

1. 在 `rules/<name>.json` 里加一行 `"deprecated": true`（保留文件本身作为历史记录）
2. 跑 `./scripts/update_index.swift` 重新生成索引 —— 弃用条目会被**自动从 `index.json` 中剔除**，App 端看不到
3. 提一个 PR，描述为何弃用

## 命名约定

- 规则文件名：小驼峰或全小写均可，**与 `name` 字段严格一致**
- `version`：字符串型（不是数字），用 `"1.0"` / `"2.3"` 这样的形式；**修改规则后必须 bump version**，否则 App 端 catalog 比对不到差异，不会触发更新
- `api`：字符串型 `"1"` ~ `"8"`，声明本规则用到的最高级特性，新增字段时记得同步抬高
- 历史拼写 `muliSources`（少一个 `t`）请**保留原样**，是 cezzu-rule 格式的一部分

## 不接受的 PR

- 直接编辑 `index.json`（请用脚本生成）
- 添加 NSFW / 涉政 / 涉黑灰产 内容站点
- 引入新的字段而不更新 `docs/rule-format.md`
- 包含可执行二进制 / 大于 1 KB 的非必要文本
