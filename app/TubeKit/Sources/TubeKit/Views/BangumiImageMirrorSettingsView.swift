import SwiftUI

/// 设置页的「网络」区块：Bangumi 图片镜像。
///
/// `lain.bgm.tv` 在国内常被 Cloudflare 挡住，表现是番剧数据正常、封面全部空白。
/// 默认走 wsrv.nl（与 Kazumi 相同的方案）；也可以填自建反代的前缀，或关闭镜像只直连。
struct BangumiImageMirrorSettingsView: View {
    @AppStorage(BangumiImageMirrorSettings.mirrorKey) private var rawMirror: String =
        BangumiImageMirrorSettings.mirrorDefault
    @State private var draft: String = ""
    @State private var showsSaved: Bool = false

    private var resolved: String { BangumiImageMirrorSettings.sanitize(draft) }
    private var isDisabled: Bool {
        BangumiImageMirrorSettings.disabledValues.contains(
            draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }
    private var isInvalid: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isDisabled && resolved.isEmpty
    }

    private var preview: String {
        let sample = URL(string: "https://lain.bgm.tv/pic/cover/l/example.jpg")!
        if let mirrored = BangumiImageMirrorSettings.mirroredURL(for: sample, mirrorPrefix: resolved) {
            return mirrored.absoluteString
        }
        return "（直连）\(sample.absoluteString)"
    }

    var body: some View {
        Section {
            TextField("https://wsrv.nl 或自建镜像前缀", text: $draft)
                .autocorrectionDisabled(true)
                .textContentType(.URL)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .onSubmit(save)
                .onAppear { draft = rawMirror }

            HStack {
                Button("保存", action: save)
                    .disabled(isInvalid || BangumiImageMirrorSettings.sanitize(rawMirror) == resolved)
                Spacer()
                if showsSaved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            Text(preview)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)

            if isInvalid {
                Text("地址必须是 http(s):// 开头的完整域名，或填写 off 关闭镜像。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(isDisabled ? "恢复默认镜像（wsrv.nl）" : "关闭镜像，只直连", role: isDisabled ? nil : .destructive) {
                draft = isDisabled ? BangumiImageMirrorSettings.mirrorDefault : "off"
                save()
            }
        } header: {
            Text("Bangumi 图片镜像")
        } footer: {
            Text(
                "封面来自 lain.bgm.tv，国内直连经常失败（表现为有文字、无封面）。默认使用 wsrv.nl 图片代理（与 Kazumi 相同的方案）；也可以填自建反代地址（如 https://img.example.com）。镜像失败会自动回落到直连；留空或填 off 表示直连。"
            )
        }
    }

    private func save() {
        guard !isInvalid else { return }
        draft = resolved.isEmpty ? "off" : resolved
        rawMirror = draft
        flashSaved()
        // 镜像变了，已缓存的失败/旧图不再有意义。
        Task { await RemoteImageCache.shared.removeAll() }
    }

    private func flashSaved() {
        withAnimation(.easeOut(duration: 0.15)) { showsSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeIn(duration: 0.2)) { showsSaved = false }
        }
    }
}
