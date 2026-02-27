import AppKit
import Foundation

let red = NSColor(calibratedRed: 239.0/255.0, green: 18.0/255.0, blue: 60.0/255.0, alpha: 1)
let white = NSColor.white
let black = NSColor(calibratedWhite: 0.12, alpha: 1)

let outputDir: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    return FileManager.default.currentDirectoryPath + "/assets/icon-variants-minimal"
}()

let size: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)

func makeBitmap() -> NSBitmapImageRep? {
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

func drawText(_ text: String, rect: NSRect, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect, withAttributes: attrs)
}

func drawSyncArrows(center: NSPoint, radius: CGFloat, line: CGFloat, color: NSColor) {
    let p1 = NSBezierPath()
    p1.lineWidth = line
    p1.lineCapStyle = .round
    p1.appendArc(withCenter: center, radius: radius, startAngle: 30, endAngle: 210)
    color.setStroke()
    p1.stroke()

    let p2 = NSBezierPath()
    p2.lineWidth = line
    p2.lineCapStyle = .round
    p2.appendArc(withCenter: center, radius: radius, startAngle: 210, endAngle: 390)
    color.setStroke()
    p2.stroke()

    let a1 = NSBezierPath()
    a1.move(to: NSPoint(x: center.x - radius - 2, y: center.y - 10))
    a1.line(to: NSPoint(x: center.x - radius + 24, y: center.y + 6))
    a1.line(to: NSPoint(x: center.x - radius + 26, y: center.y - 24))
    a1.close()
    color.setFill()
    a1.fill()

    let a2 = NSBezierPath()
    a2.move(to: NSPoint(x: center.x + radius + 2, y: center.y + 10))
    a2.line(to: NSPoint(x: center.x + radius - 24, y: center.y - 6))
    a2.line(to: NSPoint(x: center.x + radius - 26, y: center.y + 24))
    a2.close()
    color.setFill()
    a2.fill()
}

func savePNG(_ bitmap: NSBitmapImageRep, name: String) throws {
    guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
        throw NSError(domain: "ASIAIRSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try png.write(to: url)
}

func render(name: String, _ draw: () -> Void) throws {
    guard let bitmap = makeBitmap(), let ctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ASIAIRSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bitmap init failed"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    canvas.fill()

    draw()
    try savePNG(bitmap, name: name)
}

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
let outer = NSBezierPath(roundedRect: canvas.insetBy(dx: 34, dy: 34), xRadius: 220, yRadius: 220)

try render(name: "ASIAIRSync-m1-red-as-sync.png") {
    red.setFill()
    outer.fill()

    drawText("AS", rect: NSRect(x: 220, y: 460, width: 584, height: 260), fontSize: 300, weight: .bold, color: white)
    drawText("SYNC", rect: NSRect(x: 240, y: 280, width: 544, height: 100), fontSize: 98, weight: .semibold, color: white)
}

try render(name: "ASIAIRSync-m2-red-a-sync-icon.png") {
    red.setFill()
    outer.fill()

    drawText("A", rect: NSRect(x: 240, y: 500, width: 544, height: 250), fontSize: 310, weight: .heavy, color: white)
    drawSyncArrows(center: NSPoint(x: 512, y: 355), radius: 120, line: 34, color: white)
    drawText("SYNC", rect: NSRect(x: 260, y: 180, width: 504, height: 90), fontSize: 84, weight: .medium, color: white)
}

try render(name: "ASIAIRSync-m3-white-red-text.png") {
    white.setFill()
    outer.fill()

    let border = NSBezierPath(roundedRect: canvas.insetBy(dx: 58, dy: 58), xRadius: 190, yRadius: 190)
    border.lineWidth = 30
    red.setStroke()
    border.stroke()

    drawText("ASIAIR", rect: NSRect(x: 180, y: 630, width: 664, height: 140), fontSize: 128, weight: .bold, color: red)
    drawText("SYNC", rect: NSRect(x: 180, y: 430, width: 664, height: 130), fontSize: 128, weight: .bold, color: red)
    drawSyncArrows(center: NSPoint(x: 512, y: 270), radius: 92, line: 28, color: red)
}

try render(name: "ASIAIRSync-m4-red-minimal-lines.png") {
    red.setFill()
    outer.fill()

    let line1 = NSBezierPath()
    line1.lineWidth = 44
    line1.lineCapStyle = .round
    line1.move(to: NSPoint(x: 250, y: 680))
    line1.line(to: NSPoint(x: 774, y: 680))
    white.setStroke()
    line1.stroke()

    let line2 = NSBezierPath()
    line2.lineWidth = 44
    line2.lineCapStyle = .round
    line2.move(to: NSPoint(x: 250, y: 560))
    line2.line(to: NSPoint(x: 664, y: 560))
    white.setStroke()
    line2.stroke()

    drawSyncArrows(center: NSPoint(x: 512, y: 320), radius: 120, line: 34, color: white)
    drawText("ASIAIR", rect: NSRect(x: 220, y: 150, width: 584, height: 90), fontSize: 78, weight: .semibold, color: white)
}

print("Generated minimal icon variants in \(outputDir)")
