import Foundation
import Testing
@testable import CezzuKit

@Suite("BannerPaletteStore")
struct BannerPaletteStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("banner-palettes-\(UUID().uuidString).json")
    }

    private let sample = CoverColorPalette(red: 0.4, green: 0.25, blue: 0.7)

    @Test("a stored palette survives a fresh store on the same file")
    func persistsAcrossInstances() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        BannerPaletteStore(fileURL: file).store(sample, for: 42)

        let reopened = BannerPaletteStore(fileURL: file).load()
        #expect(reopened[42] == sample)
    }

    @Test("load returns empty when the file is missing")
    func missingFileLoadsEmpty() {
        let file = tempFile()
        #expect(BannerPaletteStore(fileURL: file).load().isEmpty)
    }

    @Test("corrupt json is treated as empty rather than crashing")
    func corruptFileLoadsEmpty() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try? Data("{ not json".utf8).write(to: file)

        #expect(BannerPaletteStore(fileURL: file).load().isEmpty)
    }

    @Test("storing the same id twice overwrites instead of duplicating")
    func overwriteSameID() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BannerPaletteStore(fileURL: file)

        store.store(sample, for: 7)
        let updated = CoverColorPalette(red: 0.1, green: 0.9, blue: 0.2)
        store.store(updated, for: 7)

        let loaded = BannerPaletteStore(fileURL: file).load()
        #expect(loaded.count == 1)
        #expect(loaded[7] == updated)
    }

    @Test("entries beyond the cap are evicted oldest-first")
    func evictsOldest() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BannerPaletteStore(fileURL: file)

        let total = BannerPaletteStore.maxEntries + 3
        for id in 0..<total {
            store.store(sample, for: id)
        }

        let loaded = BannerPaletteStore(fileURL: file).load()
        #expect(loaded.count == BannerPaletteStore.maxEntries)
        #expect(loaded[0] == nil)
        #expect(loaded[1] == nil)
        #expect(loaded[2] == nil)
        #expect(loaded[total - 1] == sample)
    }

    @Test("negative and large subject ids round-trip through the string-keyed file")
    func unusualIDsRoundTrip() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = BannerPaletteStore(fileURL: file)

        store.store(sample, for: Int.max)
        store.store(sample, for: -1)

        let loaded = BannerPaletteStore(fileURL: file).load()
        #expect(loaded[Int.max] == sample)
        #expect(loaded[-1] == sample)
    }
}
