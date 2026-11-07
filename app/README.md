# Tube App

本目录包含 iOS 17+ / macOS 14+ 原生应用和共享 TubeKit。

在仓库根目录执行 `bash scripts/build.sh project`，然后打开 `app/Tube.xcodeproj`。选择 `Tube-iOS` 或 `Tube-macOS` scheme。

构建与测试见 `scripts/build.sh`，发版流程见 `.github/workflows/build.yml` 与 `scripts/bump_version.sh`；DanDanPlay / Bangumi 凭证填入 `app/LocalSecrets.xcconfig`（参考同目录 example 文件）。

弹幕设置可从设置页或播放器打开。关键词屏蔽支持逐行批量添加、自动去重和删除，匹配忽略大小写及全角、半角；屏蔽词保存在本机，两处设置同步，暂停时添加屏蔽词也会立即隐藏已显示的匹配弹幕。

播放器工具栏中的 AirPlay 按钮可选择远程播放设备，支持 iOS、iPadOS 与 macOS。接收设备需支持 AirPlay；通过本地代理播放时，两端需处于可互通的局域网并允许本地网络访问。受站点鉴权或网络限制影响的资源可能无法投屏，连接真实设备后需验证播放及退出投屏恢复。
