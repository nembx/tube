# 规则格式

> 本文档是 tube-rule 协议的**唯一权威定义**。所有 `rules/*.json` 文件都必须遵循这里描述的字段、类型与语义。

tube-rule 是一组共 20 个核心字段的 JSON 规则格式，用字符串型 `api`/`version`，配 XPath 1.0 子集做 HTML 抽取。

## 完整字段表

| 字段 | 类型 | 必填 | 默认值 | 含义 |
| --- | --- | --- | --- | --- |
| `api` | **string** | ✓ | — | API 等级（`"1"` ~ `"9"`），声明本规则用到的最高级特性。兼容性以客户端实际实现的字段为准。 |
| `type` | string | ✓ | — | 当前固定为 `"anime"`。预留给未来的内容类型。 |
| `name` | string | ✓ | — | 规则唯一 id；**必须与文件名（不含 `.json`）一致**。 |
| `version` | **string** | ✓ | — | 字符串型版本号（如 `"1.0"`、`"2.3"`）；客户端按字符串相等判定"是否有更新"。 |
| `muliSources` | bool | ✓ | — | （历史拼写**保留原样**）该站点详情页是否有多条线路（多组备用源）。`true` 时 `chapterRoads` 会匹配多个容器，每个容器代表一条线路。 |
| `useWebview` | bool | ✓ | — | 播放阶段是否走 WebView 嗅探。当前所有规则都是 `true`。 |
| `useNativePlayer` | bool | ✓ | — | 是否使用客户端原生播放器（在源代码注释里被标记为已废弃，但**仍是必填**）。当前所有规则都是 `true`。 |
| `usePost` | bool | ✗ | `false` | 搜索请求是否用 POST 表单（`true`）而不是 GET（`false`）。**API ≥ 2** 才生效。 |
| `useLegacyParser` | bool | ✗ | `false` | 是否走旧版 HTML 解析路径（用于 iframe 嵌套较深的站点）。**API ≥ 4** 才生效。 |
| `adBlocker` | bool | ✗ | `false` | 是否对返回的 m3u8 manifest 做广告片段过滤。**API ≥ 5** 才生效。 |
| `userAgent` | string | ✓ | `""` | 搜索请求自定义 UA；空串 = 客户端默认随机 UA。 |
| `baseURL` | string | ✓ | — | 解析 `searchResult` / `chapterResult` 中相对链接的 base URL。 |
| `searchURL` | string | ✓ | — | 搜索 URL 模板。**字面量 `@keyword` 会被替换为 URL-encoded 关键字**。没有分页支持。 |
| `searchList` | string | ✓ | — | XPath：搜索结果页里每个结果项的容器节点。 |
| `searchName` | string | ✓ | — | XPath（相对于 `searchList` 项）：标题文本。可以以 `/text()` 结尾来直接取文本节点。 |
| `searchResult` | string | ✓ | — | XPath（相对于 `searchList` 项）：结果链接元素，取其 `@href` 解析为详情页 URL。 |
| `chapterRoads` | string | ✓ | — | XPath：详情页里每条"线路"（mirror line）的容器节点。`muliSources = true` 时一般是 `<ul>` 或 `<div>` 列表。 |
| `chapterResult` | string | ✓ | — | XPath（相对于每个 `chapterRoads` 容器）：每集的链接元素。文本作为集名，`@href` 作为播放页 URL。 |
| `referer` | string | ✗ | `""` | 搜索请求的 `Referer` 头。**API ≥ 3** 才生效；某些 CDN 拒绝空 Referer。 |
| `antiCrawlerConfig` | object | ✗ | `null` | 反爬配置子树（验证码自动求解）。**API ≥ 6** 才生效，详见下文。 |
| `searchMode` | string | ✗ | `"xpath"` | 搜索解析模式：`"xpath"`（默认，HTML + XPath）或 `"api"`（JSON API + JSONPath）。**API ≥ 8**。 |
| `chapterMode` | string | ✗ | `"xpath"` | 章节解析模式：`"xpath"` 或 `"api"`。**API ≥ 8**。 |
| `searchApiConfig` | object | ✗ | `null` | `searchMode = "api"` 时的搜索请求与 JSONPath 映射，见下文。 |
| `chapterApiConfig` | object | ✗ | `null` | `chapterMode = "api"` 时的章节请求与 JSONPath 映射，见下文。 |
| `cookies` | string | ✗ | `""` | 播放页要预置的 cookie，`"k=v; k2=v2"` 格式。**API ≥ 9** 才生效。 |
| `videoURLPattern` | string | ✗ | `""` | 嗅探结果的正则过滤 / 改写。**API ≥ 9** 才生效。 |

### `antiCrawlerConfig` 子结构

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `enabled` | bool | 是否启用反爬流程 |
| `captchaType` | int | `1` = 图片验证码（用户输入）；`2` = 自动点击按钮（如"我不是机器人"） |
| `captchaImage` | string | XPath：验证码 `<img>` 元素 |
| `captchaInput` | string | XPath：验证码输入框 |
| `captchaButton` | string | XPath：提交按钮 |

> Tube 客户端自 0.1.0-alpha.6 起消费这组字段：搜索页 HTML 命中 `captchaImage` 或 `captchaButton` 的 XPath 时，App 会抛出 `captchaRequired` 并弹出内置 `WKWebView` sheet 让用户在真浏览器里完成校验，通过后把 cookie 合并进内存级 `PluginCookieStore`，后续同规则请求自动带上。`enabled: false` 或字段缺失则走原有无反爬逻辑。

### `searchApiConfig` / `chapterApiConfig`（API 模式）

当站点提供 JSON 接口而不是 HTML 列表时，把 `searchMode` / `chapterMode` 设为 `"api"`，并用受限 JSONPath（仅 `$`、`.field`、`['field']`、`[index]`、`[*]`）描述响应映射。

**`searchApiConfig`：**

| 字段 | 含义 |
| --- | --- |
| `request.method` | `GET` / `POST` |
| `request.url` | 请求 URL 模板，可用 `@keyword` |
| `request.query` | query 字典，值可用 `@keyword` 等模板变量 |
| `listPath` | 结果数组 JSONPath（如 `$.data.videos[*]`） |
| `namePath` | 相对每条结果的标题路径（如 `$.name`） |
| `sourcePath` | 相对每条结果的来源 id / URL 路径（如 `$.id`）；API 章节请求里以 `@source` 回填 |
| `sourceTemplate` | 可选，默认空串。**API ≥ 9**。把来源 id / slug 转为详情地址，例如 `https://example.com/detail/@source.html`；非空时必须包含 `@source`，替换值按 URL component 编码，支持 `/GV@source` |

当 `chapterMode = "xpath"` 时，API 搜索的来源（或 `sourceTemplate` 结果）按 `baseURL` 解析为网页详情 URL。例如 `mgnacg` 的 `baseURL = https://www.mgnacg.com/media/` 加 id `42` 得到 `/media/42`。当 `chapterMode = "api"` 时保留来源 id，供章节 API 请求使用。

`request.bodyType` 支持 `json` / `form`。JSON `body` 保留数字、布尔、null、数组和嵌套对象类型，只在字符串值上替换模板变量；包含引号或反斜杠的关键字会被正确 JSON 转义。

**`chapterApiConfig`：**

| 字段 | 含义 |
| --- | --- |
| `request` | 同搜索，模板变量含 `@source` |
| `format` | `nested`（默认）或 `delimited` |
| `roadsPath` / `roadNamePath` / `episodesPath` / `episodeNamePath` / `episodeUrlPath` | nested 格式映射 |
| `roadNamesPath` / `roadEpisodesPath` + 分隔符 | delimited 格式映射 |
| `variables` | 从章节响应再抽命名变量（JSONPath → 模板变量，如 `slug`） |
| `episodePage.url` / `episodePage.query` | 播放页模板；可用 `@slug` `@roadIndex` `@episodeIndex` `@source` 等 |

参考规则：`rules/xfdmnext.json`（API 搜索及章节）、`rules/TvTFun.json`（API 搜索 + XPath 章节）。

### `cookies` / `videoURLPattern`（选流控制，API ≥ 9）

嗅探器默认是"抓到什么算什么"。一个播放页常常同时冒出多路流（不同清晰度、
预览片、广告垫片），这两个字段让规则能声明"我只要长这样的那一路"。

**`cookies`** —— 播放页加载**之前**写进 WebView 的 cookie，`"k=v; k2=v2"`：

```jsonc
"cookies": "quality=1080; lang=zh"
```

用于站点把清晰度 / 语言选择存在 cookie 里、播放页读 cookie 决定回哪一路流的情况。
cookie 绑定到播放页 URL 所在的域，path 固定 `/`。空片段、缺 `=`、名字为空的片段会被跳过。

**`videoURLPattern`** —— 对每一条嗅探命中做正则匹配：

| 情况 | 行为 |
| --- | --- |
| 字段为空 / 缺失 | 全放行、不改写（**默认**，既有规则行为不变） |
| 正则编译失败 | 同样全放行 —— 一条写错的正则不该让整个源播不了 |
| 不匹配 | 丢弃该条 |
| 匹配、且有命名组 `v` | 用 `v` 组的内容作为真实地址（会做一次百分号解码） |
| 匹配、无 `v` 组 | 保留原地址 |

命名组 `v` 用于站点把真地址塞在跳转参数里的情况：

```jsonc
// https://player.example/go?url=https%3A%2F%2Fcdn.example%2Freal.m3u8
//   → https://cdn.example/real.m3u8
"videoURLPattern": ".+\\?url=(?<v>.+)"
```

只挑 1080P 那一路：

```jsonc
"videoURLPattern": "(vdownload|abre-videos).*1080.*\\.(m3u8|mp4)"
```

> 同一个站点想同时提供多档清晰度时，写成多条规则（每条一个 `videoURLPattern` +
> 对应的 `cookies`），而不是一条规则里塞多个 pattern。


### 仓库专用字段（运行时不读，但工具会用）

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `deprecated` | bool | 弃用标记。`true` 时 `update_index.swift` 会把它从 `index.json` 中剔除。 |
| `author` | string | 规则作者署名。`update_index.swift` 会把它写进 catalog 条目。 |

客户端解码器会读核心字段 + API 模式字段；`deprecated` 与 `author` 是仓库工具的扩展，不影响 App 行为。

## 完整示例（带注释）

```jsonc
{
    // API 等级 6 = 用了 antiCrawlerConfig
    "api": "6",
    "type": "anime",
    "name": "exampleSite",
    "version": "1.0",

    // 详情页有多条线路（多组备用源）
    "muliSources": true,

    // 必填的 webview / native player 标记
    "useWebview": true,
    "useNativePlayer": true,

    // 搜索走 GET（默认），不需要旧解析器
    "usePost": false,
    "useLegacyParser": false,

    // 启用 m3u8 广告过滤
    "adBlocker": true,

    // 搜索请求用默认随机 UA
    "userAgent": "",

    // 链接解析 base
    "baseURL": "https://example-anime.com/",

    // 搜索模板：@keyword 会被替换为 URL-encoded 关键字
    "searchURL": "https://example-anime.com/search.html?wd=@keyword",

    // 搜索结果列表的 XPath（每条结果一个容器）
    "searchList": "//div[@class='vod-list']/div[@class='vod-item']",

    // 标题（相对 list 项），尾部 /text() 让客户端直接取文本节点
    "searchName": "//h3/a/text()",

    // 结果链接（相对 list 项），客户端取 @href
    "searchResult": "//h3/a",

    // 详情页：每条线路一个 ul
    "chapterRoads": "//ul[@class='play-list']",

    // 每条线路里每集一个 a
    "chapterResult": "//li/a",

    // 该站 CDN 拒绝空 Referer，必须传
    "referer": "https://example-anime.com/",

    // 反爬：图片验证码
    "antiCrawlerConfig": {
        "enabled": true,
        "captchaType": 1,
        "captchaImage": "//img[@class='ds-verify-img']",
        "captchaInput": "//div[4]/div[2]/div/div/input",
        "captchaButton": "//div[4]/div[2]/button"
    }
}
```

## XPath 子集

tube-rule **只支持 XPath**（不支持 CSS 选择器、不支持正则、不支持自定义 JS hook）。具体子集：

- `//`-prefixed 表达式（绝对路径）
- `@class='...'` / `@id='...'` 类的属性谓词
- Kazumi 属性子串写法 `[@class*='value']`（也支持双引号），由客户端转换为 XPath 1.0 的 `[contains(@class, 'value')]`
- `contains()`、`starts-with()` 和 `.//` 相对选择器
- 位置步 `div[2]/a` / `li[1]`
- 末尾 `/text()` 终止节点（取纯文本，自动 trim）

XPath 引擎在客户端实现为 `Kanna` (libxml2) 包装。上述属性子串语法是兼容转换，不代表支持任意 CSS 选择器。

Kazumi 历史规则中的 `captchaType = 3` / `captchaScript`、`captchaDetectType` / `captchaDetectValue` 尚未实现；Tube 当前反爬流程依据图片/按钮 XPath 检测并交给用户在 WebView 中完成。此次上游 18 个有效规则均未启用这些脚本能力。

## `searchURL` 占位符

`searchURL` 中**唯一支持的占位符是字面量 `@keyword`**，会被替换为 URL-encoded 的搜索关键字。没有：

- `{keyword}` 花括号变体
- `{page}` 分页变量
- 任何其他正则替换

如果站点搜索接口需要带页码 / 类目等额外参数，请直接写在 `searchURL` 里固定值。

## `muliSources` 拼写说明

是的，少了一个 `t`。这是 tube-rule 格式从早期就保留下来的历史拼写，已经写进了所有现存规则文件与客户端代码，**必须保留这个拼写**，请不要"修复"它。

## 索引 (`index.json`) 格式

由 `scripts/update_index.swift` 自动生成，格式为一个对象数组，每条对象的字段：

```json
[
    {
        "name": "exampleSite",
        "version": "1.0",
        "useNativePlayer": true,
        "antiCrawlerEnabled": true,
        "author": "",
        "lastUpdate": 1772874345000
    }
]
```

- `lastUpdate` 是 epoch 毫秒，优先取自 `git log -1 --format=%at <file>`，未提交时回落到文件 mtime
- `antiCrawlerEnabled` 是 `antiCrawlerConfig.enabled` 的扁平化镜像
- 弃用规则（`"deprecated": true`）**不会出现在索引里**

**不要手动编辑 `index.json`**，每次改了规则文件请重新跑 `./scripts/update_index.swift`。
