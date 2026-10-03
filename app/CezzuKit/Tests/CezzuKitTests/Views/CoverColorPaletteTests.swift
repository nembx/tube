import CoreGraphics
import Foundation
import Testing
@testable import CezzuKit

@Suite("CoverColorPalette")
struct CoverColorPaletteTests {

    @Test("clamp keeps components in 0...1")
    func clampComponents() {
        let p = CoverColorPalette(red: -0.2, green: 1.5, blue: 0.4)
        #expect(p.red == 0)
        #expect(p.green == 1)
        #expect(p.blue == 0.4)
    }

    @Test("darkened reduces luminance")
    func darkenedIsDarker() {
        let p = CoverColorPalette(red: 0.6, green: 0.4, blue: 0.8)
        let d = p.darkened
        #expect(d.red < p.red)
        #expect(d.green < p.green)
        #expect(d.blue < p.blue)
    }

    @Test("extract solid blue yields blue-dominant palette")
    func extractSolidBlue() throws {
        let image = try makeSolidImage(red: 0.15, green: 0.25, blue: 0.85)
        let palette = CoverColorExtractor.extract(from: image)
        #expect(palette.blue > palette.red)
        #expect(palette.blue > palette.green)
        #expect(palette.blue > 0.3)
    }

    @Test("extract solid red yields red-dominant palette")
    func extractSolidRed() throws {
        let image = try makeSolidImage(red: 0.9, green: 0.12, blue: 0.1)
        let palette = CoverColorExtractor.extract(from: image)
        #expect(palette.red > palette.green)
        #expect(palette.red > palette.blue)
    }

    @Test("extract from empty data returns nil")
    func extractEmptyData() {
        #expect(CoverColorExtractor.extract(from: Data()) == nil)
    }

    @Test("fallback is usable non-black")
    func fallbackNotBlack() {
        let f = CoverColorPalette.fallback
        #expect(f.red + f.green + f.blue > 0.2)
    }

    // MARK: - helpers

    private func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let w = 16, h = 16
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.context
        }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = ctx.makeImage() else { throw TestImageError.image }
        return image
    }

    private enum TestImageError: Error {
        case context, image
    }
}

@Suite("CoverColorPalette washed")
struct CoverColorPaletteWashedTests {

    /// 浅色模式底色：保留封面色相，但绝不能是纯白。
    @Test("washed stays light without going pure white")
    func washedIsLightButTinted() {
        let vivid = CoverColorPalette(red: 0.9, green: 0.1, blue: 0.2)
        let washed = vivid.washed
        #expect(washed.red > 0.9)
        #expect(washed.red < 1.0)
        // 色相顺序保留：原来红最多，washed 里红仍最多
        #expect(washed.red > washed.blue)
        #expect(washed.blue > washed.green)
    }

    /// 纯黑封面也要washed成浅色，而不是留黑。
    @Test("washed lifts even a black cover into the light range")
    func washedLiftsBlack() {
        let washed = CoverColorPalette(red: 0, green: 0, blue: 0).washed
        #expect(abs(washed.red - 0.90) < 0.0001)
        #expect(abs(washed.green - 0.90) < 0.0001)
        #expect(abs(washed.blue - 0.90) < 0.0001)
    }

    @Test("washed of white stays in range")
    func washedClampsWhite() {
        let washed = CoverColorPalette(red: 1, green: 1, blue: 1).washed
        #expect(washed.red <= 1.0)
        #expect(abs(washed.red - 1.0) < 0.0001)
    }
}

@Suite("DetailTab")
struct DetailTabTests {

    /// 吐槽改成概览底部的常驻段落，不再占 tab 栏。
    @Test("tabBarCases excludes comments but allCases keeps it")
    func tabBarExcludesComments() {
        #expect(!DetailTab.tabBarCases.contains(.comments))
        #expect(DetailTab.allCases.contains(.comments))
        #expect(DetailTab.tabBarCases.first == .overview)
        #expect(DetailTab.tabBarCases.count == DetailTab.allCases.count - 1)
    }
}
