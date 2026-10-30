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

    /// 历史里存的是落盘当时的**绝对**路径。iOS 重装 / 更新后数据容器的 UUID 会变，
    /// 旧路径指向的文件就不在了 —— 这正是「继续观看」封面一直空白、且和镜像 / 官方
    /// 站点无关的原因（file:// 根本不走网络）。文件名只由番剧身份决定、跨容器稳定，
    /// 所以按文件名在**当前**目录里重新找；找不到返回 nil，让调用方回落到海报。
    static func currentURL(forStored coverURLString: String?) -> URL? {
        guard let coverURLString, let stored = URL(string: coverURLString), stored.isFileURL else {
            return nil
        }
        let name = stored.lastPathComponent
        guard name.hasPrefix("frame-") else { return nil }
        let candidate = directoryURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
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
