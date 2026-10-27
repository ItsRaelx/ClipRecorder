import AppKit

/// Menu bar version of the app logo: the "replay" arc with an arrowhead around a dot.
/// Idle is a template image (adapts to light/dark menu bars); while recording the
/// dot turns red; paused shows pause bars instead of the dot.
enum MenuBarIcon {
    enum Style { case idle, recording, paused }

    /// - Parameter darkMenuBar: only matters for `.recording` (the one non-template state).
    static func image(_ style: Style, darkMenuBar: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ink: NSColor = style == .recording && darkMenuBar ? .white : .black
            draw(in: rect, style: style, ink: ink)
            return true
        }
        image.isTemplate = style != .recording
        image.accessibilityDescription = "ClipRecorder"
        return image
    }

    private static func draw(in rect: NSRect, style: Style, ink: NSColor) {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let r: CGFloat = 6.6
        // Gap at the upper right (same geometry as the app icon, y-up angles).
        let gapCenter: CGFloat = 58, gap: CGFloat = 70
        let start = gapCenter + gap / 2, end = gapCenter - gap / 2 + 360

        ink.setStroke()
        ink.setFill()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: r, startAngle: start, endAngle: end - 8, clockwise: false)
        arc.lineWidth = 1.7
        arc.lineCapStyle = .round
        arc.stroke()

        // Arrowhead at the arc end, pointing along the counter-clockwise direction.
        let t = (end - 360) * .pi / 180
        let p = NSPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
        let d = NSPoint(x: -sin(t), y: cos(t))   // tangent (counter-clockwise)
        let n = NSPoint(x: cos(t), y: sin(t))    // outward normal
        let tip: CGFloat = 3.0, half: CGFloat = 2.6, back: CGFloat = 1.2
        let head = NSBezierPath()
        head.move(to: NSPoint(x: p.x + d.x * tip, y: p.y + d.y * tip))
        head.line(to: NSPoint(x: p.x + n.x * half - d.x * back, y: p.y + n.y * half - d.y * back))
        head.line(to: NSPoint(x: p.x - n.x * half - d.x * back, y: p.y - n.y * half - d.y * back))
        head.close()
        head.lineJoinStyle = .round
        head.lineWidth = 0.6
        head.fill()
        head.stroke()

        switch style {
        case .idle:
            NSBezierPath(ovalIn: NSRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)).fill()
        case .recording:
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 3.3, y: c.y - 3.3, width: 6.6, height: 6.6)).fill()
        case .paused:
            NSBezierPath(roundedRect: NSRect(x: c.x - 2.4, y: c.y - 2.8, width: 1.7, height: 5.6), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: c.x + 0.7, y: c.y - 2.8, width: 1.7, height: 5.6), xRadius: 0.8, yRadius: 0.8).fill()
        }
    }
}
