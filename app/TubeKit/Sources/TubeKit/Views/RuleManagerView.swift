import SwiftUI

/// 规则管理屏：拆成两个 sub-tab —— 已安装规则 & 规则源管理。
public struct RuleManagerView: View {
    @Bindable var store: RuleStoreCoordinator

    @State private var selectedTab: Tab = .installed

    public enum Tab: Hashable { case installed, sources, browse }

    public init(store: RuleStoreCoordinator) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("已安装").tag(Tab.installed)
                Text("可安装").tag(Tab.browse)
                Text("规则源").tag(Tab.sources)
            }
            .pickerStyle(.segmented)
            .padding()

            if let message = store.lastError {
                RuleStoreErrorBanner(message: message) { store.clearLastError() }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            switch selectedTab {
            case .installed:
                InstalledRulesView(store: store)
            case .browse:
                BrowseCatalogView(store: store)
            case .sources:
                RuleSourcesView(store: store)
            }
        }
        .navigationTitle("规则")
        .task {
            if store.catalog.isEmpty { await store.refresh() }
        }
    }
}

struct InstalledRulesView: View {
    @Bindable var store: RuleStoreCoordinator

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if store.installedRules.isEmpty {
                    GlassPanel {
                        Text("还没有安装任何规则。切换到\"可安装\"挑几个吧。")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(store.installedRules) { installed in
                    GlassListRow {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(installed.name).font(.headline)
                                if store.hasUpdate(for: installed.name) {
                                    Label("有更新", systemImage: "arrow.up.circle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { installed.isEnabled },
                                        set: { newValue in
                                            Task {
                                                try? await store.setRuleEnabled(
                                                    name: installed.name, enabled: newValue
                                                )
                                            }
                                        }
                                    )
                                )
                                .labelsHidden()
                                .tubeToggleTint()
                            }
                            Text("v\(installed.version)").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if store.hasUpdate(for: installed.name) {
                                    GlassSecondaryButton("更新", systemImage: "arrow.down.circle") {
                                        Task { try? await store.update(name: installed.name) }
                                    }
                                }
                                GlassSecondaryButton("卸载", systemImage: "trash") {
                                    Task { try? await store.uninstall(name: installed.name) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct BrowseCatalogView: View {
    @Bindable var store: RuleStoreCoordinator

    var body: some View {
        let installableCatalog = store.catalog.excludingInstalled(store.installedRules)

        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    Spacer()
                    GlassSecondaryButton("刷新规则源", systemImage: "arrow.clockwise") {
                        Task { await store.refresh() }
                    }
                }
                if installableCatalog.isEmpty {
                    GlassPanel { Text("空空如也，先刷新一下试试。").foregroundStyle(.secondary) }
                }
                ForEach(installableCatalog) { entry in
                    GlassListRow {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.name).font(.headline)
                                Spacer()
                                Text("v\(entry.version)").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if entry.antiCrawlerEnabled {
                                    Label("反爬", systemImage: "shield").font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let sourceID = entry.sourceID {
                                    GlassSecondaryButton("安装", systemImage: "plus") {
                                        Task {
                                            try? await store.install(
                                                name: entry.name, fromSource: sourceID
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct RuleSourcesView: View {
    @Bindable var store: RuleStoreCoordinator
    @State private var showAddDialog = false
    @State private var newSourceName = ""
    @State private var newSourceURL = ""
    @State private var addError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    Spacer()
                    GlassPrimaryButton("添加自定义源", systemImage: "plus") {
                        newSourceName = ""
                        newSourceURL = ""
                        showAddDialog = true
                    }
                }
                ForEach(store.sources) { source in
                    GlassListRow {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(source.name).font(.headline)
                                if source.isBuiltIn {
                                    Text("内置")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.tertiary, in: Capsule())
                                }
                                Spacer()
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { source.isEnabled },
                                        set: { newValue in
                                            Task {
                                                try? await store.setSourceEnabled(
                                                    id: source.id, enabled: newValue
                                                )
                                            }
                                        }
                                    )
                                )
                                .labelsHidden()
                                .tubeToggleTint()
                            }
                            Text(source.indexURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if case .failed(let message) = store.sourceStatus[source.id] {
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if !source.isBuiltIn {
                                GlassSecondaryButton("删除", systemImage: "trash") {
                                    Task {
                                        try? await store.removeCustomSource(id: source.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .alert("添加自定义规则源", isPresented: $showAddDialog) {
            TextField("名称", text: $newSourceName)
            TextField("index.json URL", text: $newSourceURL)
            Button("取消", role: .cancel) {}
            Button("添加") {
                Task { await tryAdd() }
            }
        } message: {
            Text("URL 必须是 https，并指向一个 cezzu-rule 格式的 index.json")
        }
    }

    private func tryAdd() async {
        addError = nil
        guard let url = URL(string: newSourceURL),
            let baseURL = url.deletingLastPathComponent().absoluteString
                .replacingOccurrences(of: "..", with: "")
                .removingPercentEncoding.flatMap(URL.init(string:))
        else {
            addError = "URL 不合法"
            return
        }
        let source = RuleSource(
            name: newSourceName,
            indexURL: url,
            ruleBaseURL: baseURL,
            mirrorPrefix: nil,
            isEnabled: true,
            isBuiltIn: false
        )
        do {
            try await store.addCustomSource(source)
        } catch {
            addError = "\(error)"
        }
    }
}


/// 规则商店的失败提示条。装/更新/添加源出错时不能再让用户对着"没反应"发呆。
struct RuleStoreErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
