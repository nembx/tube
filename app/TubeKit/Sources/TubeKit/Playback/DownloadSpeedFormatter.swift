import Foundation

/// 把下行吞吐（B/s）格式化为播放器顶栏可读文案。
public enum DownloadSpeedFormatter {
    private static let mebibyte: Double = 1024 * 1024

    public static func format(bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "—" }
        if bytesPerSecond < mebibyte {
            let kb = Int((bytesPerSecond / 1024).rounded())
            return "\(kb) KB/s"
        }
        let mb = bytesPerSecond / mebibyte
        return String(format: "%.1f MB/s", mb)
    }
}
