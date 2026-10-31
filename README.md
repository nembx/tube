# Tube

原生 iPhone、iPad 和 Mac 番剧播放器，基于 [Cezzu](https://github.com/bentx2685/cezzu) 的 MIT 开源代码开发。

<img src="docs/iphone.jpg" alt="Tube 在 iPhone 上的首页" width="300">

## 功能

**找番**

- Bangumi 搜索、热门榜单、按标签浏览，详情页含简介、评分、标签、制作信息。
- 短评、长评与单集吐槽直接在 App 内查看。
- Bangumi 服务站点可切换：官方 `bgm.tv`、内置 `bangumi.lat` 镜像，或自建镜像。选镜像后搜索、封面、评论、热门全部走镜像，国内无需翻墙。

**追番**

- 本地追番收藏、观看历史，首页「继续观看」一键续播。
- 可选登录 Bangumi 账户：同步想看 / 在看 / 看过等状态，看完一集自动标记看过，追番页按状态筛选。不登录时所有功能照常可用。

**播放**

- 多视频源、线路与剧集切换，内置 19 个播放源规则，并兼容 Kazumi / Cezzu 的规则订阅与导入。
- AVPlayer 播放、倍速、后台音频，iOS 画中画与 AirPlay。
- DanDanPlay 弹幕，支持字号、透明度、显示区域、密度等设置。
- MetalFX / Anime4K 视频超分辨率（受设备和播放方式限制）。
- 可选「播放代理」，只作用于播放链路，默认关闭。

**界面**

- iPhone 底部导航，iPad 自适应布局，Mac 原生窗口与播放快捷键。
- 外观跟随系统 / 浅色 / 深色；iOS 26 / macOS 26 起启用 Liquid Glass，旧系统回退到 Material。

最低支持 **iOS 17 / macOS 14**。无自建后端，收藏与历史保存在本机，暂不提供 iCloud 同步。视频源、Bangumi 与弹幕的可用性取决于第三方服务及网络。

## 下载

前往 [Releases](https://github.com/nembx/tube/releases) 获取最新版本：iOS 为未签名 IPA（安装前需自行签名），macOS 为未公证 DMG（首次打开需在「系统设置 → 隐私与安全性」允许）。

## 来源与许可

基于 Cezzu 开发，上游 MIT 版权声明见 [LICENSE](LICENSE)，组件信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。感谢 Cezzu、Kazumi / KazumiRules、Kanna、Anime4K、Bangumi 和 DanDanPlay。应用本身不提供视频内容，请使用有权访问的来源。
