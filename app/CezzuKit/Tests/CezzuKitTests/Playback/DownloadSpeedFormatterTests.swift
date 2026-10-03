import Testing
@testable import CezzuKit

@Suite("DownloadSpeedFormatter")
struct DownloadSpeedFormatterTests {

    @Test("nil speed formats as em dash")
    func nilSpeed() {
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: nil) == "—")
    }

    @Test("below 1 MiB/s uses whole KB/s")
    func kilobytesPerSecond() {
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: 820 * 1024) == "820 KB/s")
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: 1024) == "1 KB/s")
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: 0) == "0 KB/s")
    }

    @Test("at least 1 MiB/s uses one-decimal MB/s")
    func megabytesPerSecond() {
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: 1_048_576) == "1.0 MB/s")
        #expect(DownloadSpeedFormatter.format(bytesPerSecond: 1.3 * 1024 * 1024) == "1.3 MB/s")
    }
}
