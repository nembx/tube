import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// 从封面图提取的沉浸式色板（sRGB 0…1 分量，跨平台）。
public struct CoverColorPalette: Hashable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// 缺图 / 取色失败时的默认深紫（贴近参考流媒体首页）。
    public static let fallback = CoverColorPalette(red: 0.18, green: 0.12, blue: 0.32)

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// 更深一档，给整页背景底部用。
    public var darkened: CoverColorPalette {
        CoverColorPalette(
            red: red * 0.42,
            green: green * 0.42,
            blue: blue * 0.48
        )
    }

    /// 极浅的同色调，给浅色模式整页底色用 —— 保留封面色相，但不留纯白。
    public var washed: CoverColorPalette {
        CoverColorPalette(
            red: red * 0.10 + 0.90,
            green: green * 0.10 + 0.90,
            blue: blue * 0.10 + 0.90
        )
    }

    /// 略提亮，给 banner 中部光晕。
    public var lifted: CoverColorPalette {
        CoverColorPalette(
            red: min(1, red * 1.18 + 0.04),
            green: min(1, green * 1.12 + 0.03),
            blue: min(1, blue * 1.15 + 0.05)
        )
    }

    private static func clamp(_ v: Double) -> Double {
        min(1, max(0, v))
    }
}

/// 纯 CoreGraphics / ImageIO 取色，避免 UIKit / AppKit 分叉。
///
/// 取色只需要缩略图：下载后走 ImageIO thumbnail，解码边长 ≤ `thumbnailMaxPixelSize`。
public enum CoverColorExtractor: Sendable {
    /// 下采样边长；够用且快。
    public static let sampleSize: Int = 32
    /// 解码缩略图最大边，避免拉全图进内存。
    public static let thumbnailMaxPixelSize: Int = 64

    public static func extract(from data: Data) -> CoverColorPalette? {
        guard let image = thumbnailImage(from: data) else { return nil }
        return extract(from: image)
    }

    public static func extract(from image: CGImage) -> CoverColorPalette {
        let size = sampleSize
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .fallback
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let raw = context.data else { return .fallback }

        let ptr = raw.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, weight = 0.0

        for i in 0..<(size * size) {
            let o = i * 4
            let a = Double(ptr[o + 3]) / 255.0
            guard a > 0.08 else { continue }
            // un-premultiply
            let r = Double(ptr[o + 0]) / 255.0 / a
            let g = Double(ptr[o + 1]) / 255.0 / a
            let b = Double(ptr[o + 2]) / 255.0 / a

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC - minC
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

            // 丢掉近黑 / 近白 / 低饱和灰，优先有「性格」的像素
            if lum < 0.06 || lum > 0.92 { continue }
            if sat < 0.05 && (lum < 0.18 || lum > 0.82) { continue }

            // 饱和与中等亮度加权，贴近海报主色
            let w = (0.35 + sat * 1.65) * (1.0 - abs(lum - 0.45) * 0.9) * a
            sumR += r * w
            sumG += g * w
            sumB += b * w
            weight += w
        }

        guard weight > 0.001 else {
            // 全是灰阶：退回整体平均
            return averageAll(ptr: ptr, count: size * size)
        }

        // 略压暗，避免沉浸背景过曝
        let scale = 0.78
        return CoverColorPalette(
            red: (sumR / weight) * scale,
            green: (sumG / weight) * scale,
            blue: (sumB / weight) * scale
        )
    }

    /// 下载封面后取色。失败返回 `nil`（调用方用 fallback）。
    /// 非 MainActor，可后台跑。
    public static func loadAndExtract(from url: URL) async -> CoverColorPalette? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            // 解码 + 取色放到协作线程，避免卡主线程
            return await Task.detached(priority: .utility) {
                extract(from: data)
            }.value
        } catch {
            return nil
        }
    }

    // MARK: - private

    /// ImageIO 缩略图解码：不拉全分辨率像素。
    private static func thumbnailImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func averageAll(ptr: UnsafeMutablePointer<UInt8>, count: Int) -> CoverColorPalette {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, n = 0.0
        for i in 0..<count {
            let o = i * 4
            let a = Double(ptr[o + 3]) / 255.0
            guard a > 0.08 else { continue }
            sumR += Double(ptr[o + 0]) / 255.0 / a
            sumG += Double(ptr[o + 1]) / 255.0 / a
            sumB += Double(ptr[o + 2]) / 255.0 / a
            n += 1
        }
        guard n > 0 else { return .fallback }
        return CoverColorPalette(
            red: (sumR / n) * 0.7,
            green: (sumG / n) * 0.7,
            blue: (sumB / n) * 0.7
        )
    }
}
