import SwiftUI

/// 剧集列表屏：顶部 road picker + 集数分页，下面网格显示当前 road 的剧集。
public struct EpisodeListView: View {
    public let detail: AnimeDetail
    public let rule: CezzuRule
    public var onTapEpisode: (PlaybackRequest) -> Void

    @State private var selectedRoadIndex: Int = 0
    @State private var episodePage: Int = 0

    public init(
        detail: AnimeDetail,
        rule: CezzuRule,
        onTapEpisode: @escaping (PlaybackRequest) -> Void
    ) {
        self.detail = detail
        self.rule = rule
        self.onTapEpisode = onTapEpisode
    }

    public var body: some View {
        VStack(spacing: 16) {
            if detail.roads.count > 1 {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(detail.roads.indices, id: \.self) { idx in
                        let isSelected = selectedRoadIndex == idx
                        Button {
                            selectedRoadIndex = idx
                            episodePage = 0
                        } label: {
                            Text(detail.roads[idx].label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassBackground(in: Capsule(style: .continuous))
                                .opacity(isSelected ? 1 : 0.65)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            if detail.roads.indices.contains(selectedRoadIndex) {
                let episodes = detail.roads[selectedRoadIndex].episodes
                let pageSize = 100
                let totalPages = max(1, (episodes.count + pageSize - 1) / pageSize)
                let safePage = min(episodePage, totalPages - 1)
                let pageStart = safePage * pageSize
                let pageEnd = min(pageStart + pageSize, episodes.count)

                if totalPages > 1 {
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(0..<totalPages, id: \.self) { page in
                            let start = page * pageSize + 1
                            let end = min((page + 1) * pageSize, episodes.count)
                            let isSelected = safePage == page
                            Button {
                                episodePage = page
                            } label: {
                                Text("\(start)-\(end)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassBackground(in: Capsule(style: .continuous))
                                    .opacity(isSelected ? 1 : 0.65)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(episodes[pageStart..<pageEnd].enumerated()), id: \.element.id) { _, episode in
                            Button {
                                let req = PlaybackRequest(
                                    anime: detail,
                                    roadIndex: selectedRoadIndex,
                                    episodeIndex: episode.index,
                                    rule: rule
                                )
                                onTapEpisode(req)
                            } label: {
                                GlassListRow {
                                    Text(episode.title)
                                        .font(.callout)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(detail.title)
        .onChange(of: selectedRoadIndex) { _, _ in episodePage = 0 }
    }
}
