/// 选集网格的分段规则：每 100 集一段，段签写成 `1-100` / `101-200`。
///
/// 抽出来是因为「面板打开时该停在哪一段」这条规则要能被测到 ——
/// 默认停在正在播的那一集所在的段，而不是永远第一段。
enum EpisodePagination {
    static let pageSize = 100

    static func pageCount(episodeCount: Int) -> Int {
        max(1, (episodeCount + pageSize - 1) / pageSize)
    }

    static func page(containing episodeIndex: Int, episodeCount: Int) -> Int {
        guard episodeCount > 0 else { return 0 }
        let clamped = min(max(episodeIndex, 0), episodeCount - 1)
        return clamped / pageSize
    }

    static func range(page: Int, episodeCount: Int) -> Range<Int> {
        let safePage = min(max(page, 0), pageCount(episodeCount: episodeCount) - 1)
        let start = min(safePage * pageSize, episodeCount)
        return start..<min(start + pageSize, episodeCount)
    }
}
