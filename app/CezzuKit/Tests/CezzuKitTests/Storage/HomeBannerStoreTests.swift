import Foundation
import Testing
@testable import CezzuKit

@Suite("HomeBannerStore")
struct HomeBannerStoreTests {

    private func tempStore() -> (HomeBannerStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cezzu-banner-\(UUID().uuidString).json")
        return (HomeBannerStore(fileURL: url), url)
    }

    private func item(id: Int, name: String = "N") -> BangumiItem {
        BangumiItem(
            id: id, name: name, nameCn: name,
            summary: "s", airDate: "2024-01-01",
            rank: 1, ratingScore: 8.0,
            images: .empty, tags: [BangumiTag(name: "奇幻", count: 10)]
        )
    }

    @Test("pickTop takes first maxCount items")
    func pickTopLimits() {
        let items = (1...10).map { item(id: $0) }
        let top = HomeBannerStore.pickTop(items)
        #expect(top.map(\.id) == [1, 2, 3, 4, 5])
        #expect(HomeBannerStore.pickTop(Array(items.prefix(2))).map(\.id) == [1, 2])
    }

    @Test("idsMatch compares id sequence")
    func idsMatch() {
        #expect(HomeBannerStore.idsMatch([item(id: 1), item(id: 2)], [item(id: 1), item(id: 2)]))
        #expect(!HomeBannerStore.idsMatch([item(id: 1), item(id: 2)], [item(id: 2), item(id: 1)]))
        #expect(!HomeBannerStore.idsMatch([item(id: 1)], [item(id: 1), item(id: 2)]))
    }

    @Test("empty disk load returns empty")
    func loadEmpty() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(store.load().isEmpty)
    }

    @Test("updateIfNeeded writes top five and survives restart")
    func updateWritesAndReloads() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let trending = (1...8).map { item(id: $0, name: "A\($0)") }
        #expect(store.updateIfNeeded(from: trending) == true)
        #expect(store.load().map(\.id) == [1, 2, 3, 4, 5])

        let reopened = HomeBannerStore(fileURL: url)
        #expect(reopened.load().map(\.id) == [1, 2, 3, 4, 5])
        #expect(reopened.load().first?.displayName == "A1")
    }

    @Test("same top five ids does not rewrite cache")
    func sameIDsSkipsWrite() throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = (1...5).map { item(id: $0, name: "old\($0)") }
        #expect(store.updateIfNeeded(from: first) == true)
        let mtime1 = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        // 元数据变了但 id 序列不变
        let second = (1...5).map { item(id: $0, name: "new\($0)") }
        #expect(store.updateIfNeeded(from: second) == false)
        let mtime2 = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(mtime1 == mtime2)
        // 内存仍是旧快照（不因元数据刷新）
        #expect(store.load().first?.displayName == "old1")
    }

    /// 老版本写的缓存没有 info / metaTags / heat；id 不变也必须被覆盖一次，
    /// 否则升级后 banner 永远显示不出热度和分类标签。
    @Test("stale cache missing new fields is backfilled even when ids match")
    func backfillsMissingFields() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = (1...5).map { item(id: $0, name: "old\($0)") }
        #expect(store.updateIfNeeded(from: legacy) == true)
        #expect(store.load().first?.heat == 0)

        let enriched = (1...5).map {
            item(id: $0, name: "new\($0)").withHeat(1000 + $0)
        }
        #expect(store.updateIfNeeded(from: enriched) == true)
        #expect(store.load().first?.heat == 1001)

        // 回填过一次之后就不该再重复写盘
        #expect(store.updateIfNeeded(from: enriched) == false)
    }

    @Test("needsFieldBackfill only fires when the cache is the one missing data")
    func backfillPredicate() {
        let bare = item(id: 1)
        let hot = item(id: 1).withHeat(500)
        #expect(HomeBannerStore.needsFieldBackfill(cached: [bare], fresh: [hot]))
        #expect(!HomeBannerStore.needsFieldBackfill(cached: [hot], fresh: [hot]))
        // 新数据反而缺字段（接口抽风）时不能倒着覆盖
        #expect(!HomeBannerStore.needsFieldBackfill(cached: [hot], fresh: [bare]))
        #expect(!HomeBannerStore.needsFieldBackfill(cached: [], fresh: []))
    }

    @Test("changed top five ids rewrites cache")
    func changedIDsRewrites() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(store.updateIfNeeded(from: (1...5).map { item(id: $0) }) == true)
        #expect(store.updateIfNeeded(from: (2...6).map { item(id: $0) }) == true)
        #expect(store.load().map(\.id) == [2, 3, 4, 5, 6])
    }

    @Test("empty trending leaves cache untouched")
    func emptyTrendingNoOp() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(store.updateIfNeeded(from: (1...3).map { item(id: $0) }) == true)
        #expect(store.updateIfNeeded(from: []) == false)
        #expect(store.load().map(\.id) == [1, 2, 3])
    }
}
