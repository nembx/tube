# Tube 0.1.0 验证记录

验证日期：2026-10-03。工具链：Xcode 27.0（27A266a），Swift 6.3，macOS / iOS 27 SDK。

## 已验证

- `swift test --package-path app/CezzuKit` 退出码为 0，Swift Testing 汇总为 749 tests / 120 suites。上游已有的 16 项 SwiftData 测试因命令行 runner 限制被跳过，未计作本次已验证的数据库行为。
- `Tube-macOS` Release 构建成功，保留网络客户端、服务器和用户选择文件的沙盒 entitlement，并完成本地 ad-hoc 签名。应用已实际启动，进程保持运行。
- `Tube-iOS` Release 真机目标构建成功，输出 `artifacts/Tube-ios-unsigned.ipa`。已检查 IPA 中 `Payload/Tube.app`、Info.plist 和开源许可资源。
- `Tube-iOS` Debug 模拟器目标构建成功，并在 iPhone 18 Pro / iOS 27 模拟器安装启动。截图确认首页、Bangumi 实时推荐、封面、评分与底部导航成功显示。
- 两端名称均为 Tube，版本 0.1.0 (1)，包标识为 `com.nembx.tube.iOS` / `com.nembx.tube.macOS`，最低系统为 iOS 17 / macOS 14。
- 已验证 85 个规则 JSON 可解析，订阅索引含 17 项，默认地址指向 `nembx/tube/main/cezzu-rule/`。
- Shell 脚本语法、Info.plist 格式通过检查。

## 本次调整

- 应用名称、图标、包标识、元数据请求 User-Agent、默认规则订阅、设置页仓库链接和独立缓存目录。
- 随应用打包完整第三方许可证，并提供「设置 → 开源许可」入口。
- iOS 画中画沿用系统生命周期，移除上游主动调用私有 `suspend` selector 的逻辑。
- 更新上游测试中固定的品牌和订阅 URL 断言；缓存测试等待服务端真正写入后再断言，消除客户端先收到最终字节产生的时序竞争；补齐视图测试的 MainActor 隔离。

## 验证范围

当前没有 Apple 开发者证书或 DanDanPlay 凭证，因此未验证 iPhone 真机签名安装、App Store / TestFlight 上传或在线弹幕。所有第三方规则站点没有逐个进行端到端播放测试；网络可用性以实际使用为准。AirPlay、真机画中画和跨设备播放尚未实机验证。

上游在新 SDK 下仍有部分弃用 API / 并发警告，以及 Mac 旧式图标暗色变体的资源警告；本次构建无错误。Mac 本地产物未经 Apple 公证。
