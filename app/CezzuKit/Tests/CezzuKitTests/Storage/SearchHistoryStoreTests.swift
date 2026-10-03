import SwiftData
import Testing
@testable import CezzuKit

@Suite(
    "SearchHistoryStore",
    .disabled("SwiftData ModelContainer crashes under swift-testing CLI runner; re-enable in Xcode test target")
)
@MainActor
struct SearchHistoryStoreTests {

    private func makeStore() throws -> SearchHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SearchHistoryEntry.self,
            configurations: config
        )
        return SearchHistoryStore(context: container.mainContext)
    }

    @Test("record inserts new keyword and exposes it via recent")
    func recordInsertsNewKeyword() throws {
        let store = try makeStore()
        store.record(keyword: "海贼王")

        #expect(store.recent == ["海贼王"])
    }

    @Test("record dedupes by keyword and bumps timestamp to top")
    func recordDedupesAndBumps() throws {
        let store = try makeStore()
        store.record(keyword: "海贼王")
        store.record(keyword: "鬼灭")
        store.record(keyword: "海贼王")

        #expect(store.recent == ["海贼王", "鬼灭"])
    }

    @Test("record trims whitespace and ignores empty input")
    func recordTrimsAndIgnoresEmpty() throws {
        let store = try makeStore()
        store.record(keyword: "   ")
        store.record(keyword: "  海贼王  ")

        #expect(store.recent == ["海贼王"])
    }

    @Test("delete removes the matching entry")
    func deleteRemovesEntry() throws {
        let store = try makeStore()
        store.record(keyword: "海贼王")
        store.record(keyword: "鬼灭")

        store.delete(keyword: "海贼王")

        #expect(store.recent == ["鬼灭"])
    }

    @Test("clearAll empties the store")
    func clearAllEmpties() throws {
        let store = try makeStore()
        store.record(keyword: "海贼王")
        store.record(keyword: "鬼灭")

        store.clearAll()

        #expect(store.recent.isEmpty)
    }

    @Test("record evicts the oldest entry past the cap")
    func recordEvictsOldest() throws {
        let store = try makeStore()
        for index in 0..<(SearchHistoryStore.maxEntries + 5) {
            store.record(keyword: "kw-\(index)")
        }

        #expect(store.recent.count == SearchHistoryStore.maxEntries)
        #expect(store.recent.first == "kw-\(SearchHistoryStore.maxEntries + 4)")
        #expect(!store.recent.contains("kw-0"))
    }

    @Test("recent persists across new store instances on the same container")
    func persistsAcrossInstances() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SearchHistoryEntry.self,
            configurations: config
        )
        let first = SearchHistoryStore(context: container.mainContext)
        first.record(keyword: "海贼王")

        let restarted = SearchHistoryStore(context: container.mainContext)
        #expect(restarted.recent == ["海贼王"])
    }
}

@Suite("InMemorySearchHistoryStore")
@MainActor
struct InMemorySearchHistoryStoreTests {

    @Test("record dedupes and bumps to top")
    func recordDedupes() {
        let store = InMemorySearchHistoryStore()
        store.record(keyword: "a")
        store.record(keyword: "b")
        store.record(keyword: "a")

        #expect(store.recent == ["a", "b"])
    }

    @Test("limit caps the size and evicts the oldest")
    func limitEvictsOldest() {
        let store = InMemorySearchHistoryStore(limit: 3)
        store.record(keyword: "a")
        store.record(keyword: "b")
        store.record(keyword: "c")
        store.record(keyword: "d")

        #expect(store.recent == ["d", "c", "b"])
    }

    @Test("delete removes a single keyword")
    func deleteRemovesOne() {
        let store = InMemorySearchHistoryStore(seed: ["a", "b", "c"])
        store.delete(keyword: "b")
        #expect(store.recent == ["a", "c"])
    }

    @Test("clearAll empties the store")
    func clearAllEmpties() {
        let store = InMemorySearchHistoryStore(seed: ["a", "b"])
        store.clearAll()
        #expect(store.recent.isEmpty)
    }

    @Test("record ignores whitespace-only input")
    func recordIgnoresWhitespace() {
        let store = InMemorySearchHistoryStore()
        store.record(keyword: "   ")
        store.record(keyword: "")
        #expect(store.recent.isEmpty)
    }
}
