// 앱 아이콘(AppIcon.icns) 만들기: 어두운 둥근 사각형 + 재생헤드(주황 선) + Shift 화살표.
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1, box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1),
               ending: NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))!.draw(in: bg, angle: -90)
    // 눈금자 띠
    let rulerH = box.height * 0.16
    NSColor(calibratedWhite: 0.32, alpha: 1).setFill()
    bg.addClip(); NSBezierPath(rect: NSRect(x: box.minX, y: box.maxY - rulerH, width: box.width, height: rulerH)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 재생헤드: 주황 세로선 + 위쪽 삼각형
    let orange = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.16, alpha: 1)
    orange.setFill()
    let x = box.minX + box.width * 0.64, w = box.width * 0.035
    NSBezierPath(rect: NSRect(x: x - w / 2, y: box.minY + box.height * 0.1, width: w, height: box.height * 0.78)).fill()
    let tri = NSBezierPath(), t = box.width * 0.09, top = box.maxY - rulerH * 0.15
    tri.move(to: NSPoint(x: x - t, y: top)); tri.line(to: NSPoint(x: x + t, y: top)); tri.line(to: NSPoint(x: x, y: top - t * 1.3)); tri.close(); tri.fill()
    // Shift 화살표(⇧) 윤곽
    let cx = box.minX + box.width * 0.32, by = box.minY + box.height * 0.2, aw = box.width * 0.36, ah = box.height * 0.5
    let a = NSBezierPath()
    a.move(to: NSPoint(x: cx, y: by + ah))
    a.line(to: NSPoint(x: cx + aw / 2, y: by + ah * 0.5)); a.line(to: NSPoint(x: cx + aw * 0.22, y: by + ah * 0.5))
    a.line(to: NSPoint(x: cx + aw * 0.22, y: by)); a.line(to: NSPoint(x: cx - aw * 0.22, y: by))
    a.line(to: NSPoint(x: cx - aw * 0.22, y: by + ah * 0.5)); a.line(to: NSPoint(x: cx - aw / 2, y: by + ah * 0.5)); a.close()
    a.lineWidth = box.width * 0.045; a.lineJoinStyle = .round
    NSColor.white.setStroke(); a.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
