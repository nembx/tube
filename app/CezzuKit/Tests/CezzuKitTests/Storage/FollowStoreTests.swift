import SwiftData
import Testing
@testable import CezzuKit

@Suite(
    "FollowStore",
    .disabled("SwiftData ModelContainer crashes under swift-testing CLI runner; re-enable in Xcode test target")
)
@MainActor
struct FollowStoreTests {
    private func makeStore() throws -> FollowStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FollowEntry.self,
            configurations: config
        )
        return FollowStore(context: container.mainContext)
    }

    private func makeItem(id: Int = 1, title: String = "葬送的芙莉莲") -> BangumiItem {
        BangumiItem(
            id: id,
            name: title,
            nameCn: title,
            summary: "summary",
            airDate: "2023-09-29",
            rank: 5,
            ratingScore: 9.1,
            images: .empty,
            tags: [],
            ratingTotal: 100,
            eps: 12,
            platform: "TV",
            episodeDuration: "24m"
        )
    }

    @Test("toggle inserts and removes an entry")
    func toggleEntry() throws {
        let store = try makeStore()
        let item = makeItem()

        try store.toggle(item)
        #expect(store.contains(item))
        #expect(store.items.count == 1)

        try store.toggle(item)
        #expect(!store.contains(item))
        #expect(store.items.isEmpty)
    }

    @Test("refresh preserves persisted entries")
    func refreshLoadsPersistedItems() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FollowEntry.self,
            configurations: config
        )
        let first = FollowStore(context: container.mainContext)
        try first.toggle(makeItem(id: 99, title: "摇曳露营"))

        let restarted = FollowStore(context: container.mainContext)
        #expect(restarted.items.count == 1)
        #expect(restarted.items.first?.displayName == "摇曳露营")
    }
}
