import Foundation
import Testing
@testable import CezzuKit

@Suite("History identity")
struct HistoryIdentityTests {
    @Test("identity prefers non-empty title so different sources share one key")
    func identityPrefersTitle() {
        let a = HistoryStore.identityKey(
            title: "在超市后门吸烟的二人",
            detailURL: "https://xfdmneo.example/1"
        )
        let b = HistoryStore.identityKey(
            title: "在超市后门吸烟的二人",
            detailURL: "https://tvtfun.example/1"
        )
        let c = HistoryStore.identityKey(
            title: "在超市后门吸烟的二人",
            detailURL: "https://baimao.example/1"
        )
        #expect(a == b)
        #expect(b == c)
    }

    @Test("empty title falls back to detail URL")
    func emptyTitleFallsBackToDetailURL() {
        let key = HistoryStore.identityKey(title: "   ", detailURL: "https://example.com/a")
        #expect(key == "https://example.com/a")
    }

    @Test("local frame cover detection")
    func localFrameCoverDetection() {
        #expect(HistoryStore.isLocalFrameCover("file:///tmp/frame.jpg"))
        #expect(HistoryStore.isLocalFrameCover("https://cdn.example/poster.jpg") == false)
        #expect(HistoryStore.isLocalFrameCover(nil) == false)
    }

    @Test("frame cache filename is stable for the same identity")
    func frameCacheFilenameStable() {
        let a = HistoryFrameCache.filename(for: "孤独摇滚")
        let b = HistoryFrameCache.filename(for: "孤独摇滚")
        let c = HistoryFrameCache.filename(for: "别的番")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hasPrefix("frame-"))
    }
}
