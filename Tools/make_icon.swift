// Erzeugt Resources/AppIcon.icns: ein Mac-Bildschirm, über den ein Fensterwischer zieht.
// Aufruf im Projektordner: swift Tools/make_icon.swift   (Vorschau: Resources/AppIcon-Vorschau.png)
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func sparkle(at c: NSPoint, size s: CGFloat, alpha: CGFloat = 1) {
    let p = NSBezierPath()
    let w = s * 0.22
    p.move(to: NSPoint(x: c.x, y: c.y + s))
    p.curve(to: NSPoint(x: c.x + s, y: c.y), controlPoint1: NSPoint(x: c.x + w, y: c.y + w), controlPoint2: NSPoint(x: c.x + w, y: c.y + w))
    p.curve(to: NSPoint(x: c.x, y: c.y - s), controlPoint1: NSPoint(x: c.x + w, y: c.y - w), controlPoint2: NSPoint(x: c.x + w, y: c.y - w))
    p.curve(to: NSPoint(x: c.x - s, y: c.y), controlPoint1: NSPoint(x: c.x - w, y: c.y - w), controlPoint2: NSPoint(x: c.x - w, y: c.y - w))
    p.curve(to: NSPoint(x: c.x, y: c.y + s), controlPoint1: NSPoint(x: c.x - w, y: c.y + w), controlPoint2: NSPoint(x: c.x - w, y: c.y + w))
    p.close()
    color(0xFFFFFF, alpha).setFill()
    p.fill()
}

/// Draws the icon in a 1024×1024 coordinate space (origin bottom left).
func drawIcon() {
    // Background squircle
    let bg = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGradient(colors: [color(0x5AD1FF), color(0x1E6FD9), color(0x123E9C)])!.draw(in: bg, angle: -90)
    // Soft light from the top
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [color(0xFFFFFF, 0.25), color(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Shadow under the monitor
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x001033, 0.45)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()

    // Stand
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: 462, y: 370))
    neck.line(to: NSPoint(x: 562, y: 370))
    neck.line(to: NSPoint(x: 586, y: 262))
    neck.line(to: NSPoint(x: 438, y: 262))
    neck.close()
    NSGradient(colors: [color(0xE3E8EE), color(0xB9C2CD)])!.draw(in: neck, angle: -90)
    let foot = rounded(NSRect(x: 392, y: 238, width: 240, height: 30), 15)
    NSGradient(colors: [color(0xEEF2F6), color(0xC3CBD5)])!.draw(in: foot, angle: -90)

    // Monitor body
    let body = rounded(NSRect(x: 214, y: 352, width: 596, height: 420), 42)
    color(0xF7F9FC).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Chin
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [color(0xE6EBF1), color(0xD3DAE3)])!.draw(in: NSRect(x: 214, y: 352, width: 596, height: 58), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Screen
    let screenRect = NSRect(x: 240, y: 418, width: 544, height: 328)
    let screen = rounded(screenRect, 16)
    NSGraphicsContext.saveGraphicsState()
    screen.addClip()
    // Clean part: bright, fresh
    NSGradient(colors: [color(0x8FE3FF), color(0x3FA9F5), color(0x2D6FE0)])!.draw(in: screen, angle: -60)
    // Glare
    let glare = NSBezierPath()
    glare.move(to: NSPoint(x: 240, y: 746))
    glare.line(to: NSPoint(x: 420, y: 746))
    glare.line(to: NSPoint(x: 300, y: 418))
    glare.line(to: NSPoint(x: 240, y: 418))
    glare.close()
    color(0xFFFFFF, 0.18).setFill()
    glare.fill()

    // Dirty part: right of the wiper blade
    let dirty = NSBezierPath()
    dirty.move(to: NSPoint(x: 604, y: 760))
    dirty.line(to: NSPoint(x: 800, y: 760))
    dirty.line(to: NSPoint(x: 800, y: 400))
    dirty.line(to: NSPoint(x: 514, y: 400))
    dirty.close()
    NSGraphicsContext.saveGraphicsState()
    dirty.addClip()
    NSGradient(colors: [color(0xA39C82), color(0x857E66)])!.draw(in: screenRect, angle: -90)
    let smudges: [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] = [
        (690, 680, 70, 0x6E6852, 0.28), (748, 540, 80, 0x6A644F, 0.25), (630, 500, 50, 0x726C56, 0.25),
        (720, 450, 40, 0x655F4A, 0.3), (640, 650, 36, 0xC2BBA0, 0.25), (765, 705, 30, 0xC8C1A6, 0.3),
    ]
    for (x, y, r, c, a) in smudges {
        color(c, a).setFill()
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6)).fill()
    }
    // Faint wipe streaks on the dirty side
    color(0xFFFFFF, 0.10).setStroke()
    for i in 0..<4 {
        let off = CGFloat(i) * 46
        let streak = NSBezierPath()
        streak.lineWidth = 10
        streak.lineCapStyle = .round
        streak.move(to: NSPoint(x: 650 + off, y: 740))
        streak.curve(to: NSPoint(x: 600 + off, y: 420), controlPoint1: NSPoint(x: 700 + off, y: 620), controlPoint2: NSPoint(x: 560 + off, y: 540))
        streak.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    // Sparkles on the clean side
    sparkle(at: NSPoint(x: 352, y: 640), size: 62)
    sparkle(at: NSPoint(x: 440, y: 520), size: 30, alpha: 0.9)
    sparkle(at: NSPoint(x: 312, y: 488), size: 20, alpha: 0.8)

    // Squeegee: blade lies on the line between clean and dirty, handle sticks out to the lower right.
    let mid = NSPoint(x: 559, y: 580)
    let angle = atan2(360.0, 90.0) - .pi / 2   // blade direction ≈ (90, 360)
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: mid.x, yBy: mid.y)
    t.rotate(byRadians: angle)
    t.concat()

    let sh = NSShadow()
    sh.shadowColor = color(0x000000, 0.35)
    sh.shadowBlurRadius = 18
    sh.shadowOffset = NSSize(width: 6, height: -10)
    sh.set()

    // Handle (local +x direction = towards the dirty side)
    let handle = rounded(NSRect(x: 20, y: -30, width: 290, height: 60), 30)
    NSGradient(colors: [color(0xFFB347), color(0xF07B1E), color(0xC9580C)])!.draw(in: handle, angle: 90)
    // Grip rings
    color(0xA94A0A, 0.55).setFill()
    for gx in stride(from: 200.0, through: 280.0, by: 26.0) {
        rounded(NSRect(x: gx, y: -30, width: 9, height: 60), 4).fill()
    }
    // Metal channel
    let channel = rounded(NSRect(x: -6, y: -205, width: 36, height: 410), 12)
    NSGradient(colors: [color(0xF4F6F8), color(0xAEB7C2), color(0xE1E6EB)])!.draw(in: channel, angle: 0)
    // Rubber blade
    let rubber = rounded(NSRect(x: -20, y: -198, width: 18, height: 396), 8)
    NSGradient(colors: [color(0x2B2F36), color(0x111317)])!.draw(in: rubber, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(px) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-Vorschau.png"))
