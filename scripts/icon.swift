// Build runs this after Brand.swift so every output uses the same vector paths.
import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        // Standard .icns artwork, compatible with macOS 14 and later.
        let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.64, blue: 0.66, alpha: 1), ending: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.40, alpha: 1))!.draw(in: tile, angle: -75)
        Brand.draw(in: context, size: 1024)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
// Optional SVG export is also used as the transparent foreground in Icon Composer.
if CommandLine.arguments.count > 2 {
    var commands: [String] = []
    for path in [Brand.orbit, Brand.dot] {
        path.applyWithBlock { element in
            let e = element.pointee, p = e.points
            func point(_ i: Int) -> String { "\(p[i].x),\(p[i].y)" }
            switch e.type {
            case .moveToPoint: commands.append("M\(point(0))")
            case .addLineToPoint: commands.append("L\(point(0))")
            case .addQuadCurveToPoint: commands.append("Q\(point(0)) \(point(1))")
            case .addCurveToPoint: commands.append("C\(point(0)) \(point(1)) \(point(2))")
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
    }
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 100 100\"><path transform=\"translate(0 100) scale(1 -1)\" fill=\"white\" d=\"\(commands.joined(separator: " "))\"/></svg>"
    try svg.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
}
