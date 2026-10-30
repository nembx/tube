import Foundation
import Testing
@testable import TubeKit

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

    /// 回归：历史里存的是落盘当时的绝对 file:// 路径；iOS 重装 / 更新后容器路径一变，
    /// 旧路径就指向不存在的文件，「继续观看」封面因此一直空白（和镜像 / 官方无关）。
    /// 文件名只由番剧身份决定，所以要能按文件名在当前目录里重新找回来。
    @Test("a frame cover stored under an old container path is re-resolved by filename")
    func staleFramePathResolvesByFilename() throws {
        let name = HistoryFrameCache.filename(for: "tube-test-\(UUID().uuidString)") + ".jpg"
        let current = HistoryFrameCache.directoryURL.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: HistoryFrameCache.directoryURL, withIntermediateDirectories: true
        )
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: current)
        defer { try? FileManager.default.removeItem(at: current) }

        // 另一个（已失效的）容器下的同名文件
        let stale = "file:///private/var/mobile/Containers/Data/Application/"
            + "00000000-0000-0000-0000-000000000000/Library/Application%20Support/Tube/HistoryFrames/\(name)"
        #expect(HistoryStore.isLocalFrameCover(stale))
        #expect(HistoryStore.resolvedCoverURL(for: stale) == current)

        // 文件真不在了就回 nil，让海报顶上
        let missing = stale.replacingOccurrences(of: name, with: "frame-0000000000000000.jpg")
        #expect(HistoryStore.resolvedCoverURL(for: missing) == nil)

        // 远端海报原样放行
        #expect(HistoryStore.resolvedCoverURL(for: "https://lain.bgm.tv/pic/cover/l/a.jpg")?.host == "lain.bgm.tv")
        #expect(HistoryStore.resolvedCoverURL(for: nil) == nil)
    }
}
