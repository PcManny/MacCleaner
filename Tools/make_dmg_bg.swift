// Zeichnet das Hintergrundbild für das DMG-Fenster: Pfeil von der App zum Programme-Ordner.
// Aufruf: swift Tools/make_dmg_bg.swift <ausgabe.png> <Farbe-hex> [Titel]
import AppKit
let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "dmg-background.png"
let hex = UInt32(args.count > 2 ? args[2] : "1E6FD9", radix: 16) ?? 0x1E6FD9
let title = args.count > 3 ? args[3] : "Zum Installieren in den Ordner „Programme“ ziehen"
func col(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let W = 640, H = 400
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * scale, pixelsHigh: H * scale, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.91, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // Farbiger Streifen oben
    col(hex).setFill(); NSRect(x: 0, y: H - 8, width: W, height: 8).fill()
    // Pfeil zwischen App (x≈170) und Programme (x≈470), Mitte y≈200 (von unten)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: 200)); arrow.line(to: NSPoint(x: 375, y: 200))
    arrow.lineWidth = 10; arrow.lineCapStyle = .round
    col(hex).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 395, y: 200)); head.line(to: NSPoint(x: 365, y: 222)); head.line(to: NSPoint(x: 365, y: 178)); head.close()
    col(hex).setFill(); head.fill()
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (title as NSString).draw(in: NSRect(x: 20, y: 112, width: W - 40, height: 30), withAttributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor(white: 0.25, alpha: 1), .paragraphStyle: style])
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: (out as NSString).deletingPathExtension + suffix + ".png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
