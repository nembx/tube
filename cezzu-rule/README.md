# Tube 规则库（cezzu-rule）

> **Tube App 的规则内容仓库** —— JSON 格式的资源站规则集合 + 自动生成的索引 + 贡献文档。
> 不含任何可执行代码，只有一组 JSON 规则文件与一个索引生成脚本。

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

Tube App 默认从本仓库拉取规则；用户也可以在 App 内添加任意自定义规则源，或手动导入单个 JSON 文件。

---

## 与 Kazumi 的渊源

本仓库**派生自 [KazumiRules](https://github.com/Predidit/KazumiRules)** —— [Kazumi](https://github.com/Predidit/Kazumi)（一个基于自定义规则的跨平台番剧采集播放器）的官方规则托管仓库，作者 [@Predidit](https://github.com/Predidit)。

要说清楚的几件事：

- **规则格式完全兼容。** Cezzu 直接采用了 Kazumi 的规则协议（`api` / `muliSources` / `searchList` / `chapterRoads` 等字段，含历史拼写 `muliSources` 少一个 `t` 的原样保留）。**Kazumi 的规则可以直接拿到 Cezzu 用，反之亦然。**
- **绝大多数规则的原始作者是 Kazumi 社区。** `rules/` 下的规则文件及其 XPath 表达式来自上游及其贡献者，规则快照继承自 Cezzu；可按下文流程从 KazumiRules 同步新增规则与修正。
- **API 等级沿用上游编号。** 上游 README 的能力表只列到 API 5，但上游规则里实际已经出现 6 / 7 / 8 级；本仓库沿用同一套编号，并在 [`docs/rule-format.md`](./docs/rule-format.md) 里补齐了 6（`antiCrawlerConfig` 验证码流程）与 8（`searchMode` / `chapterMode` 的 JSON API + JSONPath 模式）的字段语义 —— 这是 cezzu-rule 字段定义的唯一权威文档。
- **同步是单向的。** 本仓库从上游拉取，不往上游推；Cezzu 客户端的行为差异（如反爬走内置 WKWebView sheet）只写在本仓库文档里，不改动规则文件本身。
- **许可证一致，署名保留。** 上游 MIT，本仓库同样 MIT，并在 [`LICENSE`](./LICENSE) 中保留 `Copyright (c) 2024 Predidit` 的原始版权声明。

感谢 Kazumi 项目与它的每一位规则贡献者 ^•ﻌ•^

---

## 规则源地址

在 Tube App 的「设置 → 规则源」里填这两个地址（`indexURL` + `ruleBaseURL`，注意 base 结尾的斜杠不能少）：

**官方直连**

```
索引  https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/index.json
规则  https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/rules/
```

**ghfast 镜像**（国内直连 raw.githubusercontent.com 不稳时用，整条 URL 前面加 `https://ghfast.top/` 前缀即可）

```
索引  https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/index.json
规则  https://ghfast.top/https://raw.githubusercontent.com/nembx/tube/main/cezzu-rule/rules/
```

App 先拉 `index.json` 拿到 catalog（`name` / `version` / `lastUpdate` 等），再按需拼 `ruleBaseURL + <name>.json` 取具体规则，所以两个地址必须指向同一个 commit 下的同一份内容。换成任意 fork 或自建镜像也是同样两条：把 `nembx/tube/main/cezzu-rule` 替换掉即可。

> raw.githubusercontent.com 有 CDN 缓存（通常几分钟），push 之后 App 里不一定立刻能看到新版本，等一会儿再刷新。

## 目录结构

```
cezzu-rule/
├── README.md                ← 你正在看
├── LICENSE                  ← MIT（含上游署名）
├── CONTRIBUTING.md          ← 如何贡献新规则 / 弃用旧规则
├── index.json               ← 由 scripts/update_index.swift 生成，不要手改
├── rules/                   ← 资源站规则文件，一站点一个 JSON（当前 85 个）
│   ├── xfdmneo.json
│   ├── AGE.json
│   └── ...
├── scripts/
│   └── update_index.swift   ← 索引生成脚本（每次改 rules/ 后必须跑）
└── docs/
    └── rule-format.md       ← 规则字段 / XPath 子集 / API 等级的权威文档
```

## 上游规则状态快照

`index.json` 只收录**未弃用**的规则（`"deprecated": true` 的条目会被脚本自动剔除，但文件本身作为历史保留在 `rules/` 下）。

| 规则 | 版本 | 反爬 | 最近更新 |
| --- | --- | --- | --- |
| `7sefun` | 1.3 | — | 2026-09-01 |
| `aafun` | 1.2 | — | 2026-09-01 |
| `AGE` | 1.5 | — | 2026-09-01 |
| `akianime` | 1.4 | — | 2026-09-01 |
| `baimao` | 1.0 | — | 2026-09-01 |
| `dalvdm` | 1.0 | ✅ | 2026-09-01 |
| `DM84` | 1.4 | — | 2026-09-01 |
| `ezdmw` | 1.2 | — | 2026-09-01 |
| `giriGiriLove` | 2.4 | ✅ | 2026-09-01 |
| `gugu3` | 1.3 | — | 2026-09-01 |
| `mgnacg` | 1.0 | ✅ | 2026-09-01 |
| `moonci` | 1.0 | — | 2026-09-01 |
| `mutefun` | 1.2 | ✅ | 2026-09-01 |
| `MXdm` | 2.3 | — | 2026-09-01 |
| `sorani` | 1.0 | — | 2026-09-01 |
| `xfdmneo` | 1.1 | — | 2026-09-01 |

> 以下状态继承自上游，并非 Tube 的实时可用性验证。共 85 个规则文件，其中 17 个在索引中可用，68 个已弃用（站点失效 / 改版）。资源站生命周期普遍很短，弃用是常态。

## API 等级

规则用字符串型 `api` 字段声明自己用到的最高级特性；客户端支持等级低于它时会拒绝加载该规则。

| API | 引入的能力 | 对应字段 |
| --- | --- | --- |
| 1 | 基础 GET 搜索 + XPath 抽取 | — |
| 2 | POST 表单搜索 | `usePost` |
| 3 | 自定义 Referer | `referer` |
| 4 | 旧版 iframe 解析路径 | `useLegacyParser` |
| 5 | HLS 广告片段过滤 | `adBlocker` |
| 6 | 反爬 / 验证码流程 | `antiCrawlerConfig` |
| 7 | 客户端能力位，未引入新字段 | — |
| 8 | JSON API + JSONPath 模式 | `searchMode` / `chapterMode` / `searchApiConfig` / `chapterApiConfig` |

字段的完整语义见 [`docs/rule-format.md`](./docs/rule-format.md)。

## 快速开始

### 添加一条新规则

1. 通读 [`docs/rule-format.md`](./docs/rule-format.md)
2. 在 `rules/` 下新建 `<name>.json`，**文件名必须与 JSON 内的 `name` 字段一致**
3. 用 Tube App 的「导入规则」本地导入并测试（搜一个常见番剧名，确认能拿到结果 → 剧集列表 → 起播）
4. 跑 `./scripts/update_index.swift` 重新生成 `index.json`
5. 提 PR

### 弃用一条规则

1. 在 `rules/<name>.json` 里加 `"deprecated": true`（保留文件本身）
2. 跑 `./scripts/update_index.swift`
3. 提 PR

详见 [`CONTRIBUTING.md`](./CONTRIBUTING.md)。

## 索引脚本

```bash
./scripts/update_index.swift
```

需要 Swift 6 与 git。脚本扫描 `rules/*.json`，为每条未弃用规则生成一条 catalog 条目（`name` / `version` / `useNativePlayer` / `antiCrawlerEnabled` / `author` / `lastUpdate`）写入 `index.json`。`lastUpdate` 优先取 git 最近一次提交时间，未提交时回落到文件 mtime。

## 从上游同步

可手动与 [KazumiRules](https://github.com/Predidit/KazumiRules) 对齐：

```bash
git clone --depth 1 https://github.com/Predidit/KazumiRules /tmp/KazumiRules
# 逐个比对 rules/<name>.json 与 /tmp/KazumiRules/<name>.json，
# 合入上游的新增规则与修正（注意保留 Cezzu 扩展字段），然后：
./scripts/update_index.swift
```

上游把规则平铺在仓库根目录，本仓库统一放在 `rules/` 下，这是唯一的结构差异。

## 免责声明

本仓库只包含**指向公开网页的 XPath 选择器与 URL 模板**，不托管、不分发、不代理任何影音内容，也不破解任何 DRM。规则指向的第三方站点与本项目无关，其内容与可用性由站点自身负责。请遵守所在地区法律法规，支持正版。

## License

MIT —— 详见 [LICENSE](./LICENSE)。规则文件派生自 MIT 协议的 KazumiRules，原始版权声明已保留。
