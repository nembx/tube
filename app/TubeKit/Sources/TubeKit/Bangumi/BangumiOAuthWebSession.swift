import Foundation

#if canImport(AuthenticationServices)
    import AuthenticationServices

    /// 用系统的 `ASWebAuthenticationSession` 打开 bgm 授权页，接住回调里的 `code`。
    ///
    /// 系统窗口自带 cookie 隔离与「取消」按钮，比自己起 WKWebView 省事也更可信。
    /// 回调 scheme 必须在 Info.plist 的 `CFBundleURLTypes` 里登记（见 project.yml）。
    ///
    /// 兜底：若窗口没拦到自定义 scheme 的跳转、由系统直接把 URL 交给了 App，
    /// `TubeRoot` 的 `onOpenURL` 会走 `BangumiAuthStore.handleCallbackURL`，
    /// 再调 `cancelActive()` 把还开着的窗口收掉。
    @MainActor
    public enum BangumiOAuthWebSession {
        private static var active: PresentationProvider?

        /// 返回回调 URL。用户取消时抛 `BangumiAuthError.cancelled`。
        public static func authorize(url: URL, callbackScheme: String) async throws -> URL {
            let provider = PresentationProvider()
            active = provider
            defer { if active === provider { active = nil } }
            return try await withCheckedThrowingContinuation { continuation in
                // 必须是 @Sendable：这个枚举是 @MainActor，闭包若继承隔离，编译器会在入口
                // 插 dispatch_assert_queue(main)；而系统是在后台线程回调它的，一回调就崩。
                // CheckedContinuation 本身线程安全，直接在后台 resume 没问题。
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { @Sendable callbackURL, error in
                    if let error {
                        if let authError = error as? ASWebAuthenticationSessionError,
                            authError.code == .canceledLogin
                        {
                            BangumiAuthStore.log.notice("web session cancelled by user")
                            continuation.resume(throwing: BangumiAuthError.cancelled)
                        } else {
                            BangumiAuthStore.log.error("web session failed: \(String(describing: error), privacy: .public)")
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        BangumiAuthStore.log.error("web session finished without a callback URL")
                        continuation.resume(throwing: BangumiAuthError.cancelled)
                        return
                    }
                    BangumiAuthStore.log.info("web session intercepted callback \(callbackURL.scheme ?? "?", privacy: .public)://\(callbackURL.host ?? "?", privacy: .public)")
                    continuation.resume(returning: callbackURL)
                }
                session.presentationContextProvider = provider
                // 每次都走干净的会话：换账号登录时不会被上次残留的 bgm cookie 直接放行。
                session.prefersEphemeralWebBrowserSession = true
                provider.retain(session)
                if session.start() {
                    BangumiAuthStore.log.info("web session started, waiting for \(callbackScheme, privacy: .public)://")
                } else {
                    BangumiAuthStore.log.error("web session refused to start (no presentation anchor?)")
                    continuation.resume(throwing: BangumiAuthError.cancelled)
                }
            }
        }

        /// 登录已经从别的路径完成（`onOpenURL`），把还开着的授权窗口收掉。
        public static func cancelActive() {
            active?.cancel()
            active = nil
        }

        /// 随机 state。
        public static func makeState() -> String {
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        /// 给系统窗口一个锚点。session 本身也挂在这里，免得在回调前被释放。
        private final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
            private var session: ASWebAuthenticationSession?

            func retain(_ session: ASWebAuthenticationSession) {
                self.session = session
            }

            func cancel() {
                session?.cancel()
                session = nil
            }

            func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
                #if os(macOS)
                    return NSApplication.shared.keyWindow
                        ?? NSApplication.shared.windows.first
                        ?? ASPresentationAnchor()
                #else
                    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
                    return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
                #endif
            }
        }
    }
#endif
