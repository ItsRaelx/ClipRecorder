import AppKit
import SwiftUI

/// Dev helper: `ClipRecorder --snapshot <dir>` renders the UI to PNGs and exits.
/// Uses an off-screen window + `cacheDisplay`, so native controls render too.
@MainActor
enum Snapshots {
    static func render(to dir: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // Outside the .app bundle there's no icon – load it from the repo.
        let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/AppIcon-1024.png").standardized
        if let image = NSImage(contentsOf: icon) { NSApplication.shared.applicationIconImage = image }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState()
        state.sourceName = "Wbudowany wyświetlacz Retina"
        state.levels.update(system: 0.72, mic: 0.46)
        let fake = URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 21.06.08.mov")
        state.recentClips = [fake, URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 20.45.13.mov"),
                             URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 19.12.40.mov")]

        func popover() -> some View {
            PopoverView(state: state).background(Color(nsColor: .windowBackgroundColor))
        }

        state.status = .buffering
        snap(popover(), "popover-idle-dark", dark: true, dir: dir)
        snap(popover(), "popover-idle-light", dark: false, dir: dir)

        state.status = .recording(since: Date().addingTimeInterval(-83))
        state.markerCount = 2
        state.now = Date()
        state.message = "Dodano znacznik 2"
        snap(popover(), "popover-recording-dark", dark: true, dir: dir)
        snap(RecordingHUD(state: state), "hud", dark: true, dir: dir, background: NSColor(white: 0.55, alpha: 1))

        state.status = .paused("Wstrzymany – zasilanie z baterii")
        state.message = "MP4 gotowy (8.7 MB) – skopiowany do schowka, wklej go np. w Discordzie."
        snap(popover(), "popover-paused-light", dark: false, dir: dir)

        // Preview card with a synthetic thumbnail.
        let preview = ClipPreviewModel()
        preview.url = fake
        preview.duration = 83
        preview.fileSize = 46_800_000
        preview.thumbnail = syntheticThumbnail()
        preview.appeared = true
        preview.remaining = 0.65
        snap(ClipPreviewView(model: preview, state: state), "preview", dark: true, dir: dir, background: NSColor(white: 0.55, alpha: 1))

        snap(MenuBarPreview(), "menubar", dark: false, dir: dir)

        for section in [SettingsView.Section.recording, .audio, .shortcuts] {
            snapWindow(SettingsView.makeWindow(state: state, section: section), "settings-\(section.rawValue)", dir: dir)
        }
    }

    private static func snapWindow(_ window: NSWindow, _ name: String, dir: URL) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private static func snap<V: View>(_ view: V, _ name: String, dark: Bool, dir: URL,
                                      size: NSSize? = nil, background: NSColor? = nil) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size ?? host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isOpaque = background != nil
        window.backgroundColor = background ?? .clear
        window.contentView = host
        window.orderFrontRegardless()
        if size == nil { window.setContentSize(host.fittingSize) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))  // let SwiftUI lay out and settle
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private static func syntheticThumbnail() -> NSImage {
        let size = NSSize(width: 640, height: 360)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.16, green: 0.12, blue: 0.35, alpha: 1),
                                NSColor(red: 0.85, green: 0.33, blue: 0.3, alpha: 1)])?.draw(in: rect, angle: -30)
            NSColor.white.withAlphaComponent(0.12).setFill()
            for i in 0..<6 { NSBezierPath(roundedRect: NSRect(x: 40, y: 280 - i * 42, width: 260 - i * 25, height: 22), xRadius: 6, yRadius: 6).fill() }
            NSBezierPath(roundedRect: NSRect(x: 340, y: 60, width: 260, height: 240), xRadius: 14, yRadius: 14).fill()
            return true
        }
    }
}

/// Fake menu bar strips (light + dark) showing the three icon states.
private struct MenuBarPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            strip(dark: false)
            strip(dark: true)
        }
    }

    private func strip(dark: Bool) -> some View {
        HStack(spacing: 22) {
            item(.idle, "bufor", dark: dark)
            item(.recording, "nagrywanie  01:23", dark: dark)
            item(.paused, "pauza", dark: dark)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(dark ? Color(white: 0.17) : Color(white: 0.93))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func item(_ style: MenuBarIcon.Style, _ label: String, dark: Bool) -> some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(style, darkMenuBar: dark))
                .renderingMode(style == .recording ? .original : .template)
                .foregroundStyle(dark ? .white : .black)
            Text(label).font(.system(size: 12)).foregroundStyle(dark ? .white : .black)
        }
    }
}
