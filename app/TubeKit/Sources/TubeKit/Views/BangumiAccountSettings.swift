import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// 设置页里的「Bangumi 账户」块：登录 / 登出、同步开关、手动同步。
///
/// 两条登录路径并列：构建时配了 OAuth 凭证就显示「用 Bangumi 登录」；
/// 粘贴个人 Access Token 永远可用（开源构建默认只有这条）。
struct BangumiAccountSettings: View {
    @Environment(BangumiAuthStore.self) private var auth
    @Environment(BangumiCollectionStore.self) private var collections
    @State private var tokenInput: String = ""
    @State private var autoTrack: Bool = BangumiCollectionStore.autoTrackDefault
    @State private var isSyncingManually: Bool = false
    @State private var showsTokenLogin: Bool = false

    private let tokenPageURL = URL(string: "https://next.bgm.tv/demo/access-token")!

    var body: some View {
        Section {
            if auth.isLoggedIn {
                loggedInRows
            } else {
                loggedOutRows
            }
            if let error = auth.lastError ?? collections.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Bangumi 账户")
        } footer: {
            footer
        }
        .onAppear { autoTrack = collections.autoTrackPlayback }
    }

    // MARK: - 已登录

    @ViewBuilder
    private var loggedInRows: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.user?.displayName ?? "Bangumi 用户")
                    .font(.body.weight(.semibold))
                if let username = auth.user?.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)

        Toggle("播放时自动同步进度", isOn: $autoTrack)
            .tubeToggleTint()
            .onChange(of: autoTrack) { _, value in
                collections.autoTrackPlayback = value
            }

        Button {
            guard !isSyncingManually else { return }
            isSyncingManually = true
            Task {
                await auth.refreshUser()
                await collections.syncAll()
                isSyncingManually = false
            }
        } label: {
            HStack {
                Label("立即同步收藏", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if collections.isSyncing || isSyncingManually {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(syncSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(collections.isSyncing || isSyncingManually)

        Button(role: .destructive) {
            auth.logout()
            collections.clear()
        } label: {
            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    private var syncSummary: String {
        let count = collections.collections.count
        guard let syncedAt = collections.lastSyncedAt else {
            return count > 0 ? "\(count) 部" : "尚未同步"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: syncedAt, relativeTo: .now)
        return "\(count) 部 · \(when)"
    }

    @ViewBuilder
    private var avatar: some View {
        let shape = Circle()
        Color.clear
            .frame(width: 40, height: 40)
            .overlay {
                if let url = auth.user?.avatarURL {
                    RemoteImage(url: url) {
                        Color.secondary.opacity(0.2)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(shape)
    }

    // MARK: - 未登录

    /// 配了 OAuth 凭证时它是主入口，粘贴令牌收进「其他方式」；没配时只剩令牌一条路，直接铺开。
    @ViewBuilder
    private var loggedOutRows: some View {
        if auth.supportsOAuth {
            Button {
                Task { await signInWithOAuth() }
            } label: {
                HStack {
                    Label("用 Bangumi 账号登录", systemImage: "person.badge.key")
                    Spacer()
                    if auth.isAuthenticating {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(auth.isAuthenticating)

            DisclosureGroup("其他登录方式", isExpanded: $showsTokenLogin) {
                tokenLoginRows
            }
        } else {
            tokenLoginRows
        }
    }

    @ViewBuilder
    private var tokenLoginRows: some View {
        SecureField("粘贴 Access Token", text: $tokenInput)
            .autocorrectionDisabled(true)
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            .onSubmit { Task { await signInWithToken() } }

        Button {
            Task { await signInWithToken() }
        } label: {
            HStack {
                Label("使用令牌登录", systemImage: "key")
                Spacer()
                if auth.isAuthenticating {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .disabled(auth.isAuthenticating || tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Link(destination: tokenPageURL) {
            Label("生成 Access Token", systemImage: "safari")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if auth.isLoggedIn {
            Text("登录后，详情页可以标记想看 / 在看 / 看过；开启自动同步后，看完一集会自动在 Bangumi 标记为看过。本地收藏仍保留在本机。")
        } else if auth.supportsOAuth {
            Text("点击后会在默认浏览器打开 bgm.tv 授权页，授权完成会自动跳回本 App。也可展开「其他登录方式」粘贴个人 Access Token。令牌只保存在本机钥匙串。")
        } else {
            Text("在 next.bgm.tv/demo/access-token 生成个人 Access Token（建议有效期选最长），粘贴到上方登录。令牌只保存在本机钥匙串，不会上传。")
        }
    }

    // MARK: - Actions

    private func signInWithToken() async {
        let ok = await auth.login(accessToken: tokenInput)
        if ok {
            tokenInput = ""
        }
    }

    private func signInWithOAuth() async {
        #if os(macOS)
            // macOS 的 ASWebAuthenticationSession 会把授权交给系统默认浏览器执行，而
            // Chromium 系浏览器（实测 Helium）不会把自定义 scheme 的回调交回 App ——
            // 会话一直不结束。改走「默认浏览器 + 深链回调」：浏览器里完成授权后跳到
            // `nembx-tube://`，系统把 URL 交给 App，由 `onOpenURL` 收尾。
            guard let url = await auth.beginOAuth() else { return }
            if !NSWorkspace.shared.open(url) {
                auth.cancelOAuth()
                auth.reportError(BangumiAuthError.cancelled)
            }
        #elseif canImport(AuthenticationServices)
            guard let scheme = auth.oauthConfig.callbackScheme else { return }
            guard let url = await auth.beginOAuth() else { return }
            do {
                let callback = try await BangumiOAuthWebSession.authorize(url: url, callbackScheme: scheme)
                await auth.handleCallbackURL(callback)
            } catch BangumiAuthError.cancelled {
                // 用户自己关掉了窗口；若登录已经从 onOpenURL 那条路完成，这里什么都不用做。
                if !auth.isLoggedIn { auth.cancelOAuth() }
            } catch {
                auth.cancelOAuth()
                auth.reportError(error)
            }
        #endif
    }
}
