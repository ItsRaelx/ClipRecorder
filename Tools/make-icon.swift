// Renders the app icon. Usage: swiftc Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon out.png
import AppKit
import SwiftUI

let coral = Color(red: 1.0, green: 0.42, blue: 0.33)
let coralDeep = Color(red: 0.93, green: 0.24, blue: 0.22)

/// Counter-clockwise "replay" arc with an arrowhead – "grab what already happened".
struct ReplayArc: Shape {
    var gapCenter: Double = -60      // degrees, y-down, clockwise from +x
    var gap: Double = 62
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2
        var p = Path()
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(gapCenter - gap / 2),
                 endAngle: .degrees(gapCenter + gap / 2 - 360), clockwise: true)
        return p
    }
}

struct ArrowHead: Shape {
    var angle: Double   // where the arc ends
    var radius: CGFloat
    var size: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let t = angle * .pi / 180
        let p = CGPoint(x: c.x + radius * cos(t), y: c.y + radius * sin(t))
        let n = CGPoint(x: cos(t), y: sin(t))            // outward normal
        let d = CGPoint(x: sin(t), y: -cos(t))           // visual counter-clockwise tangent
        var path = Path()
        let tip = 1.25 * size, half = 0.85 * size, back = 0.2 * size
        path.move(to: CGPoint(x: p.x + d.x * tip, y: p.y + d.y * tip))
        path.addLine(to: CGPoint(x: p.x + n.x * half - d.x * back, y: p.y + n.y * half - d.y * back))
        path.addLine(to: CGPoint(x: p.x - n.x * half - d.x * back, y: p.y - n.y * half - d.y * back))
        path.closeSubpath()
        return path
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: 824pt squircle on a 1024 canvas
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

            // soft coral glow
            Circle()
                .fill(RadialGradient(colors: [coral.opacity(0.45), .clear], center: .center, startRadius: 60, endRadius: 360))
                .frame(width: 720, height: 720)

            // replay arc
            let arcR: CGFloat = 268
            ZStack {
                ReplayArc(gapCenter: -58, gap: 70)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 46, lineCap: .round))
                    .frame(width: arcR * 2, height: arcR * 2)
                let head = ArrowHead(angle: -58 + 35, radius: arcR, size: 58)
                head.fill(Color.white)
                head.stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineJoin: .round))
            }
            .frame(width: 1024, height: 1024)
            .compositingGroup()
            .opacity(0.96)

            // record dot
            Circle()
                .fill(RadialGradient(colors: [coral, coralDeep], center: UnitPoint(x: 0.4, y: 0.35),
                                     startRadius: 10, endRadius: 190))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 4))
                .frame(width: 290, height: 290)
                .shadow(color: coralDeep.opacity(0.6), radius: 24)
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
