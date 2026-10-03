import Foundation
import Testing
@testable import CezzuKit

@Suite("ExtractedMediaCache")
struct ExtractedMediaCacheTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func episode(_ index: Int) -> URL {
        URL(string: "https://example.com/play/\(index)")!
    }

    private func media(_ index: Int) -> ExtractedMedia {
        ExtractedMedia(url: URL(string: "https://cdn.example.com/\(index).m3u8")!, source: .xhrUrl)
    }

    @Test("a fresh entry is returned as-is")
    func returnsFreshEntry() {
        var cache = ExtractedMediaCache()
        cache.insert(media(1), for: episode(1), now: start)

        #expect(cache.value(for: episode(1), now: start.addingTimeInterval(60)) == media(1))
        #expect(cache.value(for: episode(2), now: start) == nil)
    }

    @Test("an entry past its time to live is dropped")
    func expiresEntry() {
        var cache = ExtractedMediaCache(timeToLive: 300)
        cache.insert(media(1), for: episode(1), now: start)

        // 站点地址常带时效签名，攒过头拿回来的是过期地址。
        #expect(cache.value(for: episode(1), now: start.addingTimeInterval(299)) == media(1))
        #expect(cache.value(for: episode(1), now: start.addingTimeInterval(301)) == nil)
        // 过期的那条同时被清掉，不该再占位置。
        #expect(cache.value(for: episode(1), now: start) == nil)
    }

    @Test("the oldest entry is dropped once capacity is reached")
    func evictsOldest() {
        var cache = ExtractedMediaCache(timeToLive: 300, capacity: 2)
        cache.insert(media(1), for: episode(1), now: start)
        cache.insert(media(2), for: episode(2), now: start)
        cache.insert(media(3), for: episode(3), now: start)

        #expect(cache.value(for: episode(1), now: start) == nil)
        #expect(cache.value(for: episode(2), now: start) == media(2))
        #expect(cache.value(for: episode(3), now: start) == media(3))
    }

    @Test("re-extracting the same episode refreshes its clock")
    func reinsertRefreshes() {
        var cache = ExtractedMediaCache(timeToLive: 300)
        cache.insert(media(1), for: episode(1), now: start)
        cache.insert(media(2), for: episode(1), now: start.addingTimeInterval(200))

        #expect(cache.value(for: episode(1), now: start.addingTimeInterval(400)) == media(2))
    }

    @Test("re-extracting the same episode does not consume a second slot")
    func reinsertKeepsOneSlot() {
        var cache = ExtractedMediaCache(timeToLive: 300, capacity: 2)
        cache.insert(media(1), for: episode(1), now: start)
        cache.insert(media(2), for: episode(1), now: start)
        cache.insert(media(3), for: episode(3), now: start)

        #expect(cache.value(for: episode(1), now: start) == media(2))
        #expect(cache.value(for: episode(3), now: start) == media(3))
    }

    @Test("removeAll empties the cache")
    func removeAllEmpties() {
        var cache = ExtractedMediaCache()
        cache.insert(media(1), for: episode(1), now: start)
        cache.removeAll()

        #expect(cache.value(for: episode(1), now: start) == nil)
    }
}
