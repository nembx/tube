import SwiftUI

/// 设置页的「Bangumi 服务」：选择官方站点或镜像站，解决国内直连 bgm.tv 不稳的问题。
///
/// 影响搜索、首页、详情与封面，OAuth 固定使用官方站点。
/// 默认官方 `bgm.tv`，目录镜像通过手动刷新缓存，也可以添加自建镜像。
///
/// 图片另有独立开关：`auto`（跟随站点，默认）/ `off`（直连）/ 具体代理地址。
struct BangumiSiteSettingsView: View {
    @State private var selected: BangumiSite = BangumiSiteSettings.selectedSite()
    @State private var sites: [BangumiSite] = BangumiSiteSettings.allSites()
    @State private var newSite: String = ""
    @State private var addError: String?
    @State private var isRefreshing = false
    @State private var mirrorRefreshFailed = false
    @AppStorage(BangumiImageMirrorSettings.mirrorKey) private var imageMirror: String =
        BangumiImageMirrorSettings.mirrorDefault

    var body: some View {
        let customHosts = Set(BangumiSiteSettings.customSites().map(\.host))
        Section {
            ForEach(sites) { site in
                Button {
                    select(site)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.host == site.host ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.host == site.host ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                                .foregroundStyle(.primary)
                            Text("\(site.apiDomain.host ?? "") · \(site.imageDomain.host ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        if customHosts.contains(site.host) {
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

            Button {
                Task { await refreshMirrors() }
            } label: {
                HStack {
                    Text("刷新镜像")
                    if isRefreshing {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isRefreshing)
            if mirrorRefreshFailed {
                Text("镜像列表刷新失败，已保留本地缓存。")
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                "默认使用官方 bgm.tv。点击「刷新镜像」获取并缓存镜像列表，也可以添加自建镜像。切换站点后会重新加载 Bangumi 数据，已登录状态保留。"
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
            Text("「跟随服务站点」时，封面使用所选站点的图床。仍读不到封面可以改用 wsrv.nl 或「播放代理」。")
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
        sites = BangumiSiteSettings.allSites()
        reloadBangumiStores()
    }

    private func refreshMirrors() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        mirrorRefreshFailed = false
        defer { isRefreshing = false }

        do {
            let mirrors = try await BangumiMirrorDirectory.fetch()
            let previous = BangumiSiteSettings.selectedSite()
            try BangumiSiteSettings.storeMirrorSites(mirrors)
            sites = BangumiSiteSettings.allSites()
            selected = BangumiSiteSettings.selectedSite()
            if selected != previous {
                BangumiSiteSettings.select(selected)
                reloadBangumiStores()
            }
        } catch {
            mirrorRefreshFailed = true
        }
    }

    private func add() {
        addError = nil
        guard BangumiSite.parse(newSite) != nil else {
            addError = "请输入一个合法域名，例如 mirror.example.com。"
            return
        }
        guard let site = BangumiSiteSettings.addCustomSite(newSite) else {
            addError = "该站点已在列表中。"
            return
        }
        newSite = ""
        select(site)
    }

    private func remove(_ site: BangumiSite) {
        BangumiSiteSettings.removeCustomSite(host: site.host)
        sites = BangumiSiteSettings.allSites()
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
