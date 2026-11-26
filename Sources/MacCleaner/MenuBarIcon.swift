import AppKit

enum MenuBarIcon {
    /// Kleines Schwarz-Weiß-Symbol im Stil des App-Icons: Bildschirm mit Fensterwischer,
    /// links sauber mit Glitzer, rechts ein paar Schmutzpunkte. Als Vorlage (Template),
    /// damit macOS es automatisch hell/dunkel einfärbt.
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        img.isTemplate = true
        return img
    }()

    static func draw() {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Bildschirm-Rahmen
        let body = NSBezierPath(roundedRect: NSRect(x: 1.2, y: 5.2, width: 19.6, height: 11.6), xRadius: 2, yRadius: 2)
        body.lineWidth = 1.4
        body.stroke()

        // Standfuß
        let neck = NSBezierPath()
        neck.move(to: NSPoint(x: 9.6, y: 4.6))
        neck.line(to: NSPoint(x: 12.4, y: 4.6))
        neck.line(to: NSPoint(x: 13.0, y: 2.2))
        neck.line(to: NSPoint(x: 9.0, y: 2.2))
        neck.close()
        neck.fill()
        NSBezierPath(roundedRect: NSRect(x: 6.8, y: 1.0, width: 8.4, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()

        // Glitzer auf der sauberen Seite
        sparkle(NSPoint(x: 5.0, y: 12.2), 3.6)
        sparkle(NSPoint(x: 7.6, y: 8.3), 1.7)

        // Schmutzpunkte auf der rechten Seite
        for (x, y, r) in [(15.3, 14.4, 0.75), (18.4, 13.0, 0.65), (16.3, 11.6, 0.5), (18.6, 7.6, 0.6), (15.0, 7.4, 0.45)] as [(CGFloat, CGFloat, CGFloat)] {
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
        }

        // Wischer: Gummilippe steil schräg, Griff nach rechts unten
        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: 10.0, y: 6.9))
        blade.line(to: NSPoint(x: 12.4, y: 15.1))
        blade.lineWidth = 2.0
        blade.lineCapStyle = .round
        blade.stroke()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 11.4, y: 10.8))
        handle.line(to: NSPoint(x: 17.6, y: 9.3))
        handle.lineWidth = 1.6
        handle.lineCapStyle = .round
        handle.stroke()
    }

    private static func sparkle(_ c: NSPoint, _ s: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y + s))
        p.curve(to: NSPoint(x: c.x + s, y: c.y), controlPoint1: NSPoint(x: c.x + s * 0.12, y: c.y + s * 0.12), controlPoint2: NSPoint(x: c.x + s * 0.12, y: c.y + s * 0.12))
        p.curve(to: NSPoint(x: c.x, y: c.y - s), controlPoint1: NSPoint(x: c.x + s * 0.12, y: c.y - s * 0.12), controlPoint2: NSPoint(x: c.x + s * 0.12, y: c.y - s * 0.12))
        p.curve(to: NSPoint(x: c.x - s, y: c.y), controlPoint1: NSPoint(x: c.x - s * 0.12, y: c.y - s * 0.12), controlPoint2: NSPoint(x: c.x - s * 0.12, y: c.y - s * 0.12))
        p.curve(to: NSPoint(x: c.x, y: c.y + s), controlPoint1: NSPoint(x: c.x - s * 0.12, y: c.y + s * 0.12), controlPoint2: NSPoint(x: c.x - s * 0.12, y: c.y + s * 0.12))
        p.close()
        p.fill()
    }
}
