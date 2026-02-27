import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let canvasRect = NSRect(x: 0, y: 0, width: size, height: size)
let asiairRed = NSColor(
    calibratedRed: 239.0 / 255.0,
    green: 18.0 / 255.0,
    blue: 60.0 / 255.0,
    alpha: 1.0
)
let white = NSColor.white

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

NSColor.clear.setFill()
canvasRect.fill()

let inset: CGFloat = 36
let iconRect = canvasRect.insetBy(dx: inset, dy: inset)
let rounded = NSBezierPath(roundedRect: iconRect, xRadius: 220, yRadius: 220)
asiairRed.setFill()
rounded.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let font: NSFont = {
    if let rounded = NSFont(name: "SFProRounded-Heavy", size: 286) {
        return rounded
    }
    if let alt = NSFont(name: "AvenirNext-Bold", size: 286) {
        return alt
    }
    return NSFont.systemFont(ofSize: 286, weight: .heavy)
}()

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: white,
    .paragraphStyle: paragraph,
    .kern: -2.0
]

let text = "ASync"
let textRect = NSRect(x: 90, y: 360, width: 844, height: 320)
text.draw(in: textRect, withAttributes: attrs)

guard let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
    fputs("Failed to encode PNG icon\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData.write(to: outputURL)
} catch {
    fputs("Failed to write icon PNG: \(error)\n", stderr)
    exit(1)
}

print("Generated icon PNG at \(outputPath)")
