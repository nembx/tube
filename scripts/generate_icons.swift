import AppKit

// Reproducible, vector-drawn Tube artwork; no external image assets required.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)

func render(size: Int, dark: Bool, mac: Bool) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let inset: CGFloat = mac ? 64 : 0
    let background = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset),
                                  xRadius: mac ? 200 : 0, yRadius: mac ? 200 : 0)
    let top = dark ? NSColor(srgbRed: 0.19, green: 0.17, blue: 0.34, alpha: 1) : NSColor(srgbRed: 0.43, green: 0.34, blue: 0.97, alpha: 1)
    let bottom = NSColor(srgbRed: 0.10, green: 0.08, blue: 0.24, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: background, angle: 70)

    let screen = NSBezierPath(roundedRect: NSRect(x: 214, y: 296, width: 596, height: 432), xRadius: 126, yRadius: 126)
    NSColor.white.withAlphaComponent(dark ? 0.08 : 0.12).setFill()
    screen.fill()
    NSColor.white.withAlphaComponent(0.70).setStroke()
    screen.lineWidth = 22
    screen.stroke()

    let play = NSBezierPath()
    play.move(to: NSPoint(x: 451, y: 394))
    play.line(to: NSPoint(x: 635, y: 500))
    play.curve(to: NSPoint(x: 635, y: 524), controlPoint1: NSPoint(x: 649, y: 508), controlPoint2: NSPoint(x: 649, y: 516))
    play.line(to: NSPoint(x: 451, y: 630))
    play.curve(to: NSPoint(x: 428, y: 617), controlPoint1: NSPoint(x: 440, y: 636), controlPoint2: NSPoint(x: 428, y: 630))
    play.line(to: NSPoint(x: 428, y: 407))
    play.curve(to: NSPoint(x: 451, y: 394), controlPoint1: NSPoint(x: 428, y: 394), controlPoint2: NSPoint(x: 440, y: 388))
    play.close()
    NSColor(srgbRed: 0.76, green: 1, blue: 0.78, alpha: 1).setFill()
    play.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for platform in ["iOS", "macOS"] {
    let directory = root.appendingPathComponent("app/Tube-\(platform)/Sources/Assets.xcassets/AppIcon.appiconset")
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "png" {
        let mac = platform == "macOS"
        let size = mac ? Int(file.deletingPathExtension().lastPathComponent.split(separator: "_").last!)! : 1024
        try render(size: size, dark: file.lastPathComponent.contains("dark"), mac: mac).write(to: file)
    }
}
print("Generated Tube icons for iOS and macOS.")
