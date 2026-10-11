import Foundation
import Testing
@testable import TubeKit

@Suite("SegmentCache")
struct SegmentCacheTests {

    private func entry(_ byte: UInt8, _ count: Int) -> SegmentCache.Entry {
        SegmentCache.Entry(contentType: "video/mp2t", data: Data(repeating: byte, count: count))
    }

    @Test("a stored segment comes back verbatim")
    func roundTrip() {
        var cache = SegmentCache()
        cache.insert(entry(0xAA, 100), for: "a")

        #expect(cache.value(for: "a") == entry(0xAA, 100))
        #expect(cache.value(for: "b") == nil)
        #expect(cache.totalBytes == 100)
    }

    @Test("the least recently used segment is evicted first")
    func evictsLeastRecentlyUsed() {
        var cache = SegmentCache(capacityBytes: 250, maximumEntryBytes: 250)
        cache.insert(entry(0x01, 100), for: "a")
        cache.insert(entry(0x02, 100), for: "b")
        // 读一下 a，让 b 成为最久没用的那个。
        _ = cache.value(for: "a")
        cache.insert(entry(0x03, 100), for: "c")

        #expect(cache.value(for: "b") == nil)
        #expect(cache.value(for: "a") != nil)
        #expect(cache.value(for: "c") != nil)
        #expect(cache.totalBytes == 200)
    }

    @Test("an oversized segment is refused instead of flushing everything")
    func refusesOversizedEntry() {
        var cache = SegmentCache(capacityBytes: 1000, maximumEntryBytes: 100)
        cache.insert(entry(0x01, 50), for: "small")
        cache.insert(entry(0x02, 500), for: "huge")

        #expect(cache.admits(byteCount: 500) == false)
        #expect(cache.value(for: "huge") == nil)
        #expect(cache.value(for: "small") != nil)
    }

    @Test("re-inserting the same key does not double-count its bytes")
    func replacingKeepsAccounting() {
        var cache = SegmentCache()
        cache.insert(entry(0x01, 100), for: "a")
        cache.insert(entry(0x02, 40), for: "a")

        #expect(cache.totalBytes == 40)
        #expect(cache.value(for: "a") == entry(0x02, 40))
    }

    @Test("removeAll resets the accounting")
    func removeAllResets() {
        var cache = SegmentCache()
        cache.insert(entry(0x01, 100), for: "a")
        cache.removeAll()

        #expect(cache.totalBytes == 0)
        #expect(cache.value(for: "a") == nil)
    }
}

@Suite("HTTPByteRange")
struct HTTPByteRangeTests {

    @Test("a closed range is inclusive of its end byte")
    func closedRange() {
        #expect(HTTPByteRange.parse("bytes=0-99", totalLength: 1000) == 0..<100)
        #expect(HTTPByteRange.parse("bytes=10-19", totalLength: 1000) == 10..<20)
    }

    @Test("an open range runs to the end of the body")
    func openRange() {
        #expect(HTTPByteRange.parse("bytes=900-", totalLength: 1000) == 900..<1000)
    }

    @Test("a suffix range counts back from the end")
    func suffixRange() {
        #expect(HTTPByteRange.parse("bytes=-200", totalLength: 1000) == 800..<1000)
        // 后缀比整体还长时退回整体，而不是负下标。
        #expect(HTTPByteRange.parse("bytes=-5000", totalLength: 1000) == 0..<1000)
    }

    @Test("an end past the body is clamped")
    func clampsEnd() {
        #expect(HTTPByteRange.parse("bytes=900-99999", totalLength: 1000) == 900..<1000)
    }

    @Test("malformed and out-of-bounds specs are rejected")
    func rejectsBadInput() {
        #expect(HTTPByteRange.parse("items=0-99", totalLength: 1000) == nil)
        #expect(HTTPByteRange.parse("bytes=0-99,200-299", totalLength: 1000) == nil)
        #expect(HTTPByteRange.parse("bytes=abc", totalLength: 1000) == nil)
        #expect(HTTPByteRange.parse("bytes=1000-1010", totalLength: 1000) == nil)
        #expect(HTTPByteRange.parse("bytes=50-10", totalLength: 1000) == nil)
        #expect(HTTPByteRange.parse("bytes=0-99", totalLength: 0) == nil)
    }

    @Test("the Content-Range header states an inclusive end")
    func contentRangeHeader() {
        #expect(
            HTTPByteRange.contentRangeHeader(for: 0..<100, totalLength: 1000)
                == "bytes 0-99/1000"
        )
    }
}

@Suite("ProxyConnectionHandler cacheability")
struct ProxyConnectionHandlerCacheabilityTests {

    @Test("only a whole-body 200 is a complete copy")
    func cacheableCases() {
        #expect(ProxyConnectionHandler.isCacheable(statusCode: 200, hasRangeRequest: false))
        // 206 只是一段，拿它去服务别的区间会发错数据。
        #expect(!ProxyConnectionHandler.isCacheable(statusCode: 206, hasRangeRequest: true))
        #expect(!ProxyConnectionHandler.isCacheable(statusCode: 200, hasRangeRequest: true))
        #expect(!ProxyConnectionHandler.isCacheable(statusCode: 404, hasRangeRequest: false))
    }
}
