import SwiftUI

/// 设置页的「播放代理」：只给播放链路（WebView 嗅探 + 视频流）走 HTTP 代理。
///
/// 参考 Kazumi 的 `proxyEnable` / `proxyUrl` 与 animeko 的 `ProxyConfig`：
/// 资源站或它的视频 CDN 在境外时，不开全局代理会出现「能拿到地址、一直缓冲」，
/// 在这里填本地 Clash 一类的地址即可。默认 `http://127.0.0.1:7890`。
struct PlaybackProxySettingsView: View {
    @AppStorage(PlaybackProxySettings.enabledKey) private var enabled: Bool =
        PlaybackProxySettings.enabledDefault
    @AppStorage(PlaybackProxySettings.urlKey) private var storedURL: String =
        PlaybackProxySettings.urlDefault
    @State private var draft: String = ""

    private var isInvalid: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !PlaybackProxySettings.isValid(draft) }

    var body: some View {
        Section {
            Toggle("使用播放代理", isOn: $enabled)
                .tubeToggleTint()

            if enabled {
                TextField("http://127.0.0.1:7890", text: $draft)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .onAppear { draft = storedURL }

                if isInvalid {
                    Text("格式应为 host:port，例如 127.0.0.1:7890。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("播放代理")
        } footer: {
            Text(
                "只影响播放：资源站页面嗅探和视频流都会走这个 HTTP 代理，App 的其它网络请求不受影响。适用于视频 CDN 在境外、不开全局代理时一直缓冲的情况。留空或格式错误时不会启用。"
            )
        }
        .onChange(of: draft) { _, value in
            if PlaybackProxySettings.isValid(value) {
                storedURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
