import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把播放器截到的当前帧存成本地 JPEG，供「最近观看 / 继续观看」当封面。
///
/// 用 ImageIO 写盘，避免 UIKit / AppKit 分叉。
enum HistoryFrameCache {
    private static let folderName = "HistoryFrames"

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tube", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// 按 identity（番剧标题或 detailURL）生成稳定文件名，覆盖写。
    static func save(image: CGImage, identity: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("\(filename(for: identity)).jpg")
        try writeJPEG(image: image, to: fileURL)
        return fileURL
    }

    static func filename(for identity: String) -> String {
        // 稳定、文件系统安全；不暴露原始标题。
        let digest = identity.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "frame-%016llx", digest)
    }

    private static func writeJPEG(image: CGImage, to url: URL) throws {
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw HistoryFrameCacheError.cannotCreateDestination
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw HistoryFrameCacheError.finalizeFailed
        }
    }
}

enum HistoryFrameCacheError: Error {
    case cannotCreateDestination
    case finalizeFailed
}
