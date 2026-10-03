import Foundation
import SwiftUI

/// 规则触发验证码时的交互 sheet：内嵌 `CaptchaWebView`，
/// 让用户在真 WebKit 里完成人机校验，成功后把 cookie 塞进 `PluginCookieStore`。
///
/// iOS / macOS 共用一套实现，靠 `.presentationDetents` 在手机上变成半屏下拉层。
public struct CaptchaVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let url: URL
    private let ruleName: String
    private let userAgent: String
    private let onSuccess: () -> Void

    @State private var handle: CaptchaWebViewHandle?
    @State private var isCompleting = false

    public init(
        url: URL,
        ruleName: String,
        userAgent: String,
        onSuccess: @escaping () -> Void
    ) {
        self.url = url
        self.ruleName = ruleName
        self.userAgent = userAgent
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("请在下方完成验证，成功后点击「已完成验证」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CaptchaWebView(url: url, userAgent: userAgent) { newHandle in
                    Task { @MainActor in
                        handle = newHandle
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .layoutPriority(1)

                Button {
                    Task { await completeVerification() }
                } label: {
                    if isCompleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("已完成验证")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(handle == nil || isCompleting)
                .padding()
            }
            .navigationTitle("验证码")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        #if os(iOS)
            .presentationDetents([.large])
        #else
            .frame(minWidth: 640, idealWidth: 760, minHeight: 560, idealHeight: 720)
        #endif
    }

    @MainActor
    private func completeVerification() async {
        guard let handle, !isCompleting else { return }
        isCompleting = true
        defer { isCompleting = false }

        let host = url.host ?? ""
        let cookies = await handle.collectCookies(matching: host)
        await PluginCookieStore.shared.merge(cookies, for: ruleName)
        onSuccess()
        dismiss()
    }
}
