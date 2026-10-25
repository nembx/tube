import SwiftUI

/// 设置页的「Bangumi 服务」：选择官方站点或镜像站，解决国内直连 bgm.tv 不稳的问题。
///
/// 影响范围：搜索 / 首页 / 详情（API）、封面（图床）、登录页与换 token（OAuth）。
/// 默认官方 `bgm.tv`；内置 `bangumi.lat` 镜像，也可以添加自建镜像（同一套子域规则：
/// `api.<host>` / `lain.<host>` / `<host>`）。
///
/// 图片另有独立开关：`auto`（跟随站点，默认）/ `off`（直连）/ 具体代理地址。
struct BangumiSiteSettingsView: View {
    @State private var selected: BangumiSite = BangumiSiteSettings.selectedSite()
    @State private var customSites: [BangumiSite] = BangumiSiteSettings.customSites()
    @State private var newSite: String = ""
    @State private var addError: String?
    @AppStorage(BangumiImageMirrorSettings.mirrorKey) private var imageMirror: String =
        BangumiImageMirrorSettings.mirrorDefault

    var body: some View {
        Section {
            ForEach(BangumiSite.presets + customSites) { site in
                Button {
                    select(site)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.host == site.host ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.host == site.host ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                                .foregroundStyle(.primary)
                            Text("api.\(site.host) · lain.\(site.host)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        // 内置站点（官方 / bangumi.lat）不可删；自定义镜像给一个明确的删除按钮
                        // —— Form 里 swipeActions 在 macOS 上不生效，必须有可见入口。
                        if !BangumiSite.presets.contains(site) {
                            Button {
                                remove(site)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("删除 \(site.name)")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                TextField("添加镜像站，如 mirror.example.com", text: $newSite)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                Button("添加", action: add)
                    .disabled(BangumiSite.parse(newSite) == nil)
            }
            if let addError {
                Text(addError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Bangumi 服务")
        } footer: {
            Text(
                "默认使用官方 bgm.tv。国内直连不稳时可以切到 bangumi.lat 镜像，或添加自建镜像。镜像需要同时提供 api.<域名>、lain.<域名> 与网页登录页；切换后会重新加载 Bangumi 数据，已登录状态保留。"
            )
        }

        Section {
            Picker("封面图片", selection: $imageMirror) {
                Text("跟随服务站点").tag("auto")
                Text("直连").tag("off")
                Text("wsrv.nl 图片代理").tag("https://wsrv.nl")
            }
            Text(imageSourceHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("封面图片")
        } footer: {
            Text("「跟随服务站点」时：官方站点直连 lain.bgm.tv；镜像站点改用 lain.<镜像域名>。仍读不到封面可以改用 wsrv.nl 或「播放代理」。")
        }
        .onChange(of: imageMirror) { _, _ in
            Task { await RemoteImageCache.shared.removeAll() }
        }
    }

    private var imageSourceHint: String {
        let sample = URL(string: "https://lain.bgm.tv/pic/cover/l/example.jpg")!
        let resolved = BangumiImageMirrorSettings.sanitize(imageMirror)
        if let url = BangumiImageMirrorSettings.mirroredURL(for: sample, mirrorPrefix: resolved, site: selected) {
            return "示例：\(url.absoluteString)"
        }
        return "示例：（直连）\(sample.absoluteString)"
    }

    private func select(_ site: BangumiSite) {
        guard site.host != selected.host else { return }
        BangumiSiteSettings.select(site)
        selected = site
        reloadBangumiStores()
    }

    private func add() {
        addError = nil
        guard let site = BangumiSite.parse(newSite) else {
            addError = "请输入一个合法域名，例如 mirror.example.com。"
            return
        }
        guard BangumiSiteSettings.addCustomSite(newSite) != nil else {
            addError = "该站点已在列表中。"
            return
        }
        customSites = BangumiSiteSettings.customSites()
        newSite = ""
        select(site)
    }

    private func remove(_ site: BangumiSite) {
        BangumiSiteSettings.removeCustomSite(host: site.host)
        customSites = BangumiSiteSettings.customSites()
        if selected.host == site.host {
            selected = BangumiSiteSettings.selectedSite()
            reloadBangumiStores()
        }
    }

    /// 站点变了：重建 API 客户端与登录态，让后续请求与 OAuth 都指向新站点。
    /// 重启 App 同样生效（两者都在初始化时读设置）。
    private func reloadBangumiStores() {
        NotificationCenter.default.post(name: .bangumiSiteChanged, object: nil)
    }
}

extension Notification.Name {
    /// 用户在设置里切换了 Bangumi 服务站点。
    public static let bangumiSiteChanged = Notification.Name("tube.bangumi.siteChanged")
}
