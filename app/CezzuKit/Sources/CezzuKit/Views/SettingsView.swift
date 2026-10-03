import SwiftUI

/// 设置屏：v1 只有"本地代理开关"。
public struct SettingsView: View {
    @Environment(RuleStoreCoordinator.self) private var ruleStore
    private let repositoryURL = URL(string: "https://github.com/nembx/tube")!
    private let kazumiAcknowledgement = try! AttributedString(
        markdown:
            "Tube 基于 [Cezzu](https://github.com/bentx2685/cezzu)（MIT）开发，感谢 [Kazumi](https://github.com/Predidit/Kazumi)、Bangumi、DanDanPlay 与 Anime4K。"
    )

    @AppStorage(PlaybackSettings.enableLocalProxyKey) private var enableLocalProxy: Bool =
        PlaybackSettings.enableLocalProxyDefault

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("启用本地代理", isOn: $enableLocalProxy)
                    .cezzuToggleTint()
            } header: {
                Text("播放")
            } footer: {
                Text(
                    "部分资源站要求自定义 Referer / User-Agent；本地反代会在播放器和站点之间转发请求并注入这些头部。\n关闭后，遇到这类规则将退化为最大努力模式（可能播放失败）。"
                )
            }

            Section("弹幕") {
                NavigationLink {
                    Form {
                        DanmakuSettingsContent(showsAdvancedOptions: true)
                    }
                    .formStyle(.grouped)
                    .navigationTitle("弹幕设置")
                } label: {
                    Text("弹幕设置")
                }
            }

            DanDanPlayCredentialsSettings()

            Section("数据源") {
                NavigationLink {
                    RuleManagerView(store: ruleStore)
                } label: {
                    Label("规则", systemImage: "list.bullet.rectangle")
                }
            }

            Section {
                Link(destination: repositoryURL) {
                    Label("GitHub 仓库", systemImage: "link")
                }
                NavigationLink("开源许可") {
                    ScrollView {
                        Text(Self.openSourceNotices)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("开源许可")
                }
            } header: {
                Text("关于 Tube")
            } footer: {
                Text(kazumiAcknowledgement)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }

    private static let openSourceNotices: String = {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "完整许可证见 https://github.com/nembx/tube"
        }
        return text
    }()
}
