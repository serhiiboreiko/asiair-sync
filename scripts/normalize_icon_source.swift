import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: normalize_icon_source.swift <input-png-path> <output-png-path>\n", stderr)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let outputSize = 1024

guard let sourceImage = NSImage(contentsOfFile: inputPath) else {
    fputs("Failed to load image: \(inputPath)\n", stderr)
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: outputSize,
    pixelsHigh: outputSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
),
let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: outputSize, height: outputSize).fill()
sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: outputSize, height: outputSize),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
    fputs("Failed to encode normalized PNG\n", stderr)
    exit(1)
}

do {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try pngData.write(to: outputURL)
} catch {
    fputs("Failed to write normalized PNG: \(error)\n", stderr)
    exit(1)
}

print("Normalized icon source to \(outputPath)")
