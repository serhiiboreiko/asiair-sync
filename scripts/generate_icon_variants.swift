import AppKit
import Foundation

let asiairRed = NSColor(
    calibratedRed: 239.0 / 255.0,
    green: 18.0 / 255.0,
    blue: 60.0 / 255.0,
    alpha: 1.0
)

let dark = NSColor(calibratedWhite: 0.09, alpha: 1.0)
let white = NSColor.white

let outputDir: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    return FileManager.default.currentDirectoryPath + "/assets/icon-variants"
}()

let size: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

func makeBitmap(size: CGFloat) -> NSBitmapImageRep? {
    NSBitmapImageRep(
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
    )
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    text.draw(in: rect, withAttributes: attrs)
}

func point(on center: NSPoint, radius: CGFloat, angleDegrees: CGFloat) -> NSPoint {
    let radians = angleDegrees * .pi / 180
    return NSPoint(
        x: center.x + cos(radians) * radius,
        y: center.y + sin(radians) * radius
    )
}

func drawArrowHead(tip: NSPoint, directionDegrees: CGFloat, size: CGFloat, color: NSColor) {
    let r = directionDegrees * .pi / 180
    let dx = cos(r)
    let dy = sin(r)
    let baseCenter = NSPoint(x: tip.x - dx * size, y: tip.y - dy * size)
    let perp = NSPoint(x: -dy, y: dx)

    let left = NSPoint(x: baseCenter.x + perp.x * size * 0.55, y: baseCenter.y + perp.y * size * 0.55)
    let right = NSPoint(x: baseCenter.x - perp.x * size * 0.55, y: baseCenter.y - perp.y * size * 0.55)

    let tri = NSBezierPath()
    tri.move(to: tip)
    tri.line(to: left)
    tri.line(to: right)
    tri.close()

    color.setFill()
    tri.fill()
}

func drawSyncSymbol(center: NSPoint, radius: CGFloat, lineWidth: CGFloat, color: NSColor) {
    let arc1 = NSBezierPath()
    arc1.lineWidth = lineWidth
    arc1.lineCapStyle = .round
    arc1.appendArc(withCenter: center, radius: radius, startAngle: 40, endAngle: 200)
    color.setStroke()
    arc1.stroke()

    let arc2 = NSBezierPath()
    arc2.lineWidth = lineWidth
    arc2.lineCapStyle = .round
    arc2.appendArc(withCenter: center, radius: radius, startAngle: 220, endAngle: 380)
    color.setStroke()
    arc2.stroke()

    let tip1 = point(on: center, radius: radius, angleDegrees: 200)
    let tip2 = point(on: center, radius: radius, angleDegrees: 380)

    drawArrowHead(tip: tip1, directionDegrees: 290, size: lineWidth * 1.05, color: color)
    drawArrowHead(tip: tip2, directionDegrees: 110, size: lineWidth * 1.05, color: color)
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
        throw NSError(domain: "ASIAIRSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try png.write(to: url)
}

func renderVariant(name: String, draw: () -> Void) throws {
    guard let bitmap = makeBitmap(size: size), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ASIAIRSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bitmap setup failed"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    canvas.fill()

    draw()

    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try writePNG(bitmap, to: url)
}

let manager = FileManager.default
try manager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let outer = canvas.insetBy(dx: 34, dy: 34)

try renderVariant(name: "ASIAIRSync-v1-red-solid.png") {
    let bg = roundedRect(outer, radius: 220)
    asiairRed.setFill()
    bg.fill()

    drawText("ASIAIR", in: NSRect(x: 220, y: 770, width: 584, height: 120), size: 88, weight: .bold, color: white)
    drawText("AS", in: NSRect(x: 250, y: 370, width: 524, height: 340), size: 300, weight: .heavy, color: white)
    drawSyncSymbol(center: NSPoint(x: 512, y: 250), radius: 92, lineWidth: 34, color: white)
}

try renderVariant(name: "ASIAIRSync-v2-white-card.png") {
    let bg = roundedRect(outer, radius: 220)
    white.setFill()
    bg.fill()

    let border = roundedRect(outer.insetBy(dx: 16, dy: 16), radius: 200)
    border.lineWidth = 28
    asiairRed.setStroke()
    border.stroke()

    drawText("ASIAIR", in: NSRect(x: 220, y: 760, width: 584, height: 120), size: 86, weight: .bold, color: asiairRed)
    drawText("AS", in: NSRect(x: 250, y: 390, width: 524, height: 320), size: 292, weight: .heavy, color: asiairRed)
    drawSyncSymbol(center: NSPoint(x: 512, y: 250), radius: 90, lineWidth: 32, color: asiairRed)
}

try renderVariant(name: "ASIAIRSync-v3-dark-red-center.png") {
    let bg = roundedRect(outer, radius: 220)
    dark.setFill()
    bg.fill()

    let inner = roundedRect(NSRect(x: 176, y: 180, width: 672, height: 672), radius: 170)
    asiairRed.setFill()
    inner.fill()

    drawText("AS", in: NSRect(x: 272, y: 435, width: 480, height: 280), size: 270, weight: .heavy, color: white)
    drawSyncSymbol(center: NSPoint(x: 512, y: 310), radius: 82, lineWidth: 30, color: white)
    drawText("SYNC", in: NSRect(x: 280, y: 150, width: 464, height: 90), size: 68, weight: .semibold, color: white)
}

try renderVariant(name: "ASIAIRSync-v4-red-circle.png") {
    let bg = roundedRect(outer, radius: 220)
    asiairRed.setFill()
    bg.fill()

    let circle = NSBezierPath(ovalIn: NSRect(x: 208, y: 220, width: 608, height: 608))
    white.setFill()
    circle.fill()

    drawText("AS", in: NSRect(x: 282, y: 438, width: 460, height: 270), size: 260, weight: .heavy, color: asiairRed)
    drawSyncSymbol(center: NSPoint(x: 512, y: 320), radius: 86, lineWidth: 30, color: asiairRed)
    drawText("ASIAIR", in: NSRect(x: 250, y: 780, width: 524, height: 120), size: 84, weight: .bold, color: white)
}

print("Generated icon variants in \(outputDir)")
