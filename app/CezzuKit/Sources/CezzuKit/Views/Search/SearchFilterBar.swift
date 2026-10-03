import SwiftUI

/// 一行筛选 chip + 展开面板。取代原来的 DisclosureGroup 表单：
/// 每个面只要一次点击就能看见全部候选值，选完即收，不用先展开再往下找。
struct SearchFilterBar: View {
    @Bindable var model: SearchViewModel
    @Binding var expandedFacet: SearchFacet?
    @Binding var newTagDraft: String
    var isTagDraftFocused: FocusState<Bool>.Binding

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    facetChip(.sort, title: "排序", detail: model.selectedSort.title)
                    facetChip(.year, title: "年份")
                    facetChip(.rating, title: "评分")
                    facetChip(.tag, title: "标签")

                    if model.hasActiveAdvancedFilter {
                        SearchChip(title: "重置", systemImage: "arrow.counterclockwise") {
                            model.resetAdvancedFilter()
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let expandedFacet {
                facetPanel(expandedFacet)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !activeFilters.isEmpty {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(activeFilters) { filter in
                        SearchChip(
                            title: filter.title,
                            isSelected: true,
                            isRemovable: true,
                            accessibilityTitle: "移除筛选 \(filter.title)"
                        ) {
                            clear(filter)
                        }
                    }
                }
            }
        }
        .animation(SearchStyle.panelTransition, value: expandedFacet)
        .animation(SearchStyle.panelTransition, value: activeFilters)
    }

    /// 生效中的筛选值，逐个可摘 —— 不用再翻回对应面板选「不限」。
    private var activeFilters: [SearchActiveFilter] {
        SearchActiveFilter.chips(
            tags: model.selectedTags,
            ratingMin: model.ratingMin,
            yearMin: model.yearMin,
            yearMax: model.yearMax,
            currentYear: currentYear
        )
    }

    private func clear(_ filter: SearchActiveFilter) {
        switch filter.kind {
        case .tag(let tag):
            model.removeTag(tag)
        case .rating:
            model.ratingMin = nil
            model.advancedFilterChanged()
        case .year:
            model.yearMin = nil
            model.yearMax = nil
            model.advancedFilterChanged()
        }
    }

    @ViewBuilder
    private func facetChip(_ facet: SearchFacet, title: String, detail: String? = nil) -> some View {
        SearchChip(
            title: title,
            systemImage: facet.systemImage,
            detail: detail,
            isSelected: expandedFacet == facet,
            accessibilityTitle: [title, detail].compactMap { $0 }.joined(separator: " ")
        ) {
            expandedFacet = expandedFacet == facet ? nil : facet
            if facet != .tag {
                isTagDraftFocused.wrappedValue = false
            }
        }
    }

    @ViewBuilder
    private func facetPanel(_ facet: SearchFacet) -> some View {
        SearchFacetPanel {
            switch facet {
            case .sort:
                sortOptions
            case .year:
                yearOptions
            case .rating:
                ratingOptions
            case .tag:
                tagOptions
            }
        }
    }

    @ViewBuilder
    private var sortOptions: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach([BangumiSearchSort.match, .heat, .score], id: \.self) { sort in
                SearchChip(title: sort.title, isSelected: model.selectedSort == sort) {
                    model.selectedSort = sort
                    model.sortChanged()
                    expandedFacet = nil
                }
            }
        }
    }

    @ViewBuilder
    private var yearOptions: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(SearchYearPreset.presets(currentYear: currentYear)) { preset in
                SearchChip(
                    title: preset.title,
                    isSelected: preset.matches(min: model.yearMin, max: model.yearMax)
                ) {
                    model.yearMin = preset.min
                    model.yearMax = preset.max
                    model.advancedFilterChanged()
                    expandedFacet = nil
                }
            }
        }
    }

    @ViewBuilder
    private var ratingOptions: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            SearchChip(title: "不限", isSelected: model.ratingMin == nil) {
                model.ratingMin = nil
                model.advancedFilterChanged()
                expandedFacet = nil
            }
            ForEach(SearchRatingPreset.thresholds, id: \.self) { threshold in
                SearchChip(
                    title: SearchRatingPreset.title(for: threshold),
                    isSelected: model.ratingMin == threshold
                ) {
                    model.ratingMin = threshold
                    model.advancedFilterChanged()
                    expandedFacet = nil
                }
            }
        }
    }

    @ViewBuilder
    private var tagOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("", text: $newTagDraft, prompt: Text("自定义标签…").foregroundColor(SearchStyle.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(SearchStyle.textPrimary)
                    .tint(.white)
                    .focused(isTagDraftFocused)
                    .submitLabel(.done)
                    .onSubmit(commitTagDraft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        Capsule(style: .continuous)
                            .fill(SearchStyle.surfaceRaised)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(SearchStyle.hairline, lineWidth: 1)
                            }
                    }
                SearchChip(title: "添加", systemImage: "plus", action: commitTagDraft)
                    .opacity(trimmedDraft.isEmpty ? 0.4 : 1)
                    .disabled(trimmedDraft.isEmpty)
            }
            SearchTagCloud(model: model)
        }
    }

    private var trimmedDraft: String {
        newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitTagDraft() {
        let trimmed = trimmedDraft
        guard !trimmed.isEmpty else { return }
        let alreadySelected = model.selectedTags.contains(trimmed)
        model.addTag(trimmed)
        newTagDraft = ""
        if !alreadySelected {
            model.advancedFilterChanged()
        }
    }
}

/// 常用标签云。点一下加进筛选，再点一下摘掉。
struct SearchTagCloud: View {
    @Bindable var model: SearchViewModel

    var body: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(SearchTagSuggestion.popular, id: \.self) { tag in
                let isSelected = model.selectedTags.contains(tag)
                SearchChip(title: tag, isSelected: isSelected) {
                    if isSelected {
                        model.removeTag(tag)
                    } else {
                        model.addTag(tag)
                        model.advancedFilterChanged()
                    }
                }
            }
        }
    }
}

/// idle 态的「热门标签」整段。
struct SearchTagCloudSection: View {
    @Bindable var model: SearchViewModel
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchSectionHeader(eyebrow: "TAGS", title: title)
            SearchTagCloud(model: model)
        }
    }
}

/// idle 态的「最近搜索」整段。一个 chip 两个热区：正文重搜、右侧 × 删除。
struct SearchHistorySection: View {
    @Bindable var model: SearchViewModel
    let limit: Int
    var onSelect: (String) -> Void

    var body: some View {
        let keywords = Array(model.historyKeywords.prefix(limit))
        if !keywords.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SearchSectionHeader(eyebrow: "RECENT", title: "最近搜索") {
                    Button("清空") {
                        model.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(SearchStyle.textTertiary)
                }
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(keywords, id: \.self) { keyword in
                        historyChip(keyword)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historyChip(_ keyword: String) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelect(keyword)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text(keyword)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(SearchStyle.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.deleteHistory(keyword)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SearchStyle.textTertiary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除“\(keyword)”")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(SearchStyle.surface)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(SearchStyle.hairline, lineWidth: 1)
                }
        }
    }
}
