import SwiftUI

/// 兼容旧路由的结果屏：展示 Bangumi 搜索结果。
public struct ResultsView: View {
    @Bindable var model: SearchViewModel
    var onTapResult: (BangumiItem) -> Void

    public init(model: SearchViewModel, onTapResult: @escaping (BangumiItem) -> Void) {
        self.model = model
        self.onTapResult = onTapResult
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(model.results) { item in
                    Button {
                        onTapResult(item)
                    } label: {
                        BangumiCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .clipped()
                }
                if model.isSearching && model.results.isEmpty {
                    GlassPanel {
                        ProgressView("搜索中…")
                    }
                }
                if !model.isSearching && model.hasSearched && model.results.isEmpty {
                    GlassPanel {
                        Text("没有结果")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("结果：\(model.text)")
    }
}
