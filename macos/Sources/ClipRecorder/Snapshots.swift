import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Dev helper: `ClipRecorder --snapshot <dir>` renders the UI to PNGs and exits.
/// Uses off-screen windows + `cacheDisplay`, so native controls render too.
/// Most screens come in `-light` and `-dark` variants (the docs pick one per GitHub theme).
@MainActor
enum Snapshots {
    static func render(to dir: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // Start from default settings in the snapshot's own domain (bare binary or the
        // `.snapshots` bundle from scripts/snapshots.sh) – never the real app's settings.
        let domain = Bundle.main.bundleIdentifier ?? "ClipRecorder"
        if Bundle.main.bundleIdentifier == nil || domain.hasSuffix(".snapshots") {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.set(true, forKey: "migratedLegacyDefaults")
        }
        // Outside the .app bundle there's no icon – load it from the repo.
        let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/AppIcon-1024.png").standardized
        if let image = NSImage(contentsOf: icon) { NSApplication.shared.applicationIconImage = image }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CloudService.offline = true  // never touch the real Keychain from a snapshot
        let plist = icon.deletingLastPathComponent().appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String {
            SettingsView.version = version
        }
        let state = AppState()
        state.userPaused = false
        state.includeSystemAudio = true
        state.includeMic = true
        state.sourceName = "Wbudowany wyświetlacz Retina"
        state.runningAppsOverride = ["com.apple.Safari", "com.apple.MobileSMS", "com.apple.mail", "com.apple.Notes",
                                     "com.apple.Music", "com.apple.FaceTime", "com.apple.iCal", "com.apple.Passwords"]
            .compactMap { id in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                return AppState.AppChoice(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        state.excludedBundleIDs = ["com.apple.MobileSMS", "com.apple.Passwords"]
        state.levels.update(system: 0.72, mic: 0.46)
        let fake = URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 21.06.08.mov")
        state.recentClips = [fake, URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 20.45.13.mov"),
                             URL(fileURLWithPath: "/tmp/Klip 2026-10-27 o 19.12.40.mov")]
        for (i, url) in state.recentClips.enumerated() {
            state.clipInfo.preload(url, .init(thumbnail: syntheticThumbnail(variant: i), duration: [83, 60, 214][i],
                                               size: [46_800_000, 31_200_000, 118_000_000][i],
                                               created: Date().addingTimeInterval(-[600, 4_000, 90_000][i])))
        }
        state.cloud.rememberLink(URL(string: "https://clip.secc.me/c/x8Fk2Qa")!, for: state.recentClips[1])

        func popover() -> some View {
            PopoverView(state: state).background(Color(nsColor: .windowBackgroundColor))
        }
        func both<V: View>(_ name: String, _ view: @autoclosure () -> V) {
            snap(view(), "\(name)-light", dark: false, dir: dir)
            snap(view(), "\(name)-dark", dark: true, dir: dir)
        }

        // Popover states
        state.status = .buffering
        both("popover-idle", popover())

        state.status = .recording(since: Date().addingTimeInterval(-83))
        state.markerCount = 2
        state.now = Date()
        state.message = "Dodano znacznik 2"
        both("popover-recording", popover())
        state.message = nil
        snap(RecordingHUD(state: state), "hud", dark: true, dir: dir)

        state.status = .paused("Wstrzymane na baterii")
        both("popover-paused-power", popover())

        state.userPaused = true
        state.status = .paused("Wstrzymane do 21:45")
        both("popover-paused-timed", popover())
        state.userPaused = false

        state.status = .failed("Zezwól na nagrywanie ekranu w Ustawieniach systemowych → Prywatność i ochrona → Nagrywanie ekranu i dźwięku systemowego.")
        both("popover-permission", popover())

        state.status = .buffering
        state.cloud.preview(account: nil, pendingLogin: .init(userCode: "WDJB-MJHT", verificationURL: URL(string: "https://clip.secc.me/device")!))
        both("popover-login", popover())

        let account = CloudService.Account(id: "u1", name: "Kuba", email: "kuba@example.com", username: "kuba", defaultVisibility: "unlisted")
        let quota = #"{"plan":{"name":"Free","expiresAt":null,"maxClipBytes":500000000,"storageBytes":5000000000,"uploadsPerDay":50},"usage":{"bytes":1240000000,"uploadsToday":3}}"#
        state.cloud.preview(account: account, quotaJSON: quota)
        state.message = "Link skopiowany."
        both("popover-signed-in", popover())
        state.message = nil

        state.updater.preview(.init(version: "1.1.0", url: URL(string: "https://github.com/ItsRaelx/ClipRecorder/releases")!))
        both("popover-update", popover())
        state.updater.preview(nil)

        // Preview card (always dark), on a transparent background.
        let preview = ClipPreviewModel()
        preview.url = fake
        preview.duration = 83
        preview.fileSize = 46_800_000
        preview.thumbnail = syntheticThumbnail(variant: 0)
        preview.appeared = true
        preview.remaining = 0.65
        func card() -> some View { ClipPreviewView(model: preview, state: state) }
        snap(card(), "preview", dark: true, dir: dir)
        state.shares[fake] = 0.62
        snap(card(), "preview-uploading", dark: true, dir: dir)
        state.shares[fake] = nil
        state.cloud.rememberLink(URL(string: "https://clip.secc.me/c/x8Fk2Qa")!, for: fake)
        snap(card(), "preview-shared", dark: true, dir: dir)
        state.cloud.forgetLink(for: fake)
        state.cloud.preview(account: nil, pendingLogin: .init(userCode: "WDJB-MJHT", verificationURL: URL(string: "https://clip.secc.me/device")!))
        snap(card(), "preview-login", dark: true, dir: dir)
        state.cloud.preview(account: account, quotaJSON: quota)

        snap(MenuBarPreview(), "menubar", dark: false, dir: dir)

        // Hero images for the README: wallpaper + menu bar + popover + preview card.
        state.status = .buffering
        state.message = nil
        for dark in [false, true] {
            snap(HeroView(state: state, preview: preview), "hero-\(dark ? "dark" : "light")", dark: dark, dir: dir,
                 size: HeroView.size)
        }

        // Settings, every section; the account section signed in and signed out.
        for section in SettingsView.Section.allCases {
            for dark in [false, true] {
                snapWindow(SettingsView.makeWindow(state: state, section: section),
                           "settings-\(section.rawValue)-\(dark ? "dark" : "light")", dark: dark, dir: dir)
            }
        }
        state.cloud.preview(account: nil)
        for dark in [false, true] {
            snapWindow(SettingsView.makeWindow(state: state, section: .account),
                       "settings-account-signed-out-\(dark ? "dark" : "light")", dark: dark, dir: dir)
        }

        // Trim window with a generated demo clip.
        let demo = FileManager.default.temporaryDirectory.appendingPathComponent("Klip 2026-10-27 o 21.06.08.mov")
        if makeDemoClip(at: demo) {
            TrimWindowController.show(demo) { _ in }
            RunLoop.main.run(until: Date().addingTimeInterval(5))  // filmstrip thumbnails load lazily
            if let window = NSApp.windows.first(where: { $0.title.hasPrefix("Przytnij") }) {
                window.appearance = NSAppearance(named: .darkAqua)
                // Video layers don't show up in cacheDisplay – the picture and the first filmstrip
                // cell (drawn from the live layer) get the first frame as a plain image instead.
                if let player = window.contentView as? AVPlayerView {
                    let controls: CGFloat = 70  // trim bar at the bottom
                    for (rect, scaling) in [(NSRect(x: 0, y: controls, width: player.bounds.width, height: player.bounds.height - controls),
                                             NSImageScaling.scaleProportionallyUpOrDown),
                                            (NSRect(x: 96, y: 15, width: 94, height: 42), .scaleAxesIndependently)] {
                        let frame = NSImageView(frame: rect)
                        frame.image = syntheticThumbnail(variant: 0)
                        frame.imageScaling = scaling
                        player.addSubview(frame)
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                snapWindowContents(window, "trim", dir: dir)
                window.close()
            }
            try? FileManager.default.removeItem(at: demo)
        }
    }

    private static func snapWindow(_ window: NSWindow, _ name: String, dark: Bool, dir: URL) {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        snapWindowContents(window, name, dir: dir)
        window.orderOut(nil)
    }

    private static func snapWindowContents(_ window: NSWindow, _ name: String, dir: URL) {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
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

    /// A made-up "screen": gradient with a few UI-like blocks (no real screen content in the docs).
    static func syntheticThumbnail(variant: Int = 0, shift: CGFloat = 0) -> NSImage {
        let palettes: [(NSColor, NSColor)] = [
            (NSColor(red: 0.16, green: 0.12, blue: 0.35, alpha: 1), NSColor(red: 0.85, green: 0.33, blue: 0.3, alpha: 1)),
            (NSColor(red: 0.05, green: 0.22, blue: 0.3, alpha: 1), NSColor(red: 0.2, green: 0.7, blue: 0.6, alpha: 1)),
            (NSColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 1), NSColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 1)),
        ]
        let (from, to) = palettes[variant % palettes.count]
        let size = NSSize(width: 640, height: 360)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [from, to])?.draw(in: rect, angle: -30)
            NSColor.white.withAlphaComponent(0.12).setFill()
            for i in 0..<6 { NSBezierPath(roundedRect: NSRect(x: 40, y: 280 - i * 42, width: 260 - i * 25, height: 22), xRadius: 6, yRadius: 6).fill() }
            NSBezierPath(roundedRect: NSRect(x: 340 + shift, y: 60, width: 260, height: 240), xRadius: 14, yRadius: 14).fill()
            return true
        }
    }

    /// Short H.264 clip of the synthetic screen (for the trim window).
    private static func makeDemoClip(at url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720,
        ])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let frames = 30 * 12
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(1_000) }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { return false }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let image = syntheticThumbnail(variant: 0, shift: CGFloat(sin(Double(i) / 20) * 30))
                var rect = NSRect(x: 0, y: 0, width: 1280, height: 720)
                if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                    ctx.draw(cg, in: rect)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return writer.status == .completed
    }
}

/// Desktop mock-up: wallpaper, menu bar with the app's icon, the open popover and a preview card.
private struct HeroView: View {
    static let size = NSSize(width: 1280, height: 940)
    let state: AppState
    let preview: ClipPreviewModel
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    /// Center of the app's menu bar icon (fixed-width items from the right edge).
    private var iconX: CGFloat { Self.size.width - 12 - 130 - 4 * 28 - 18 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            menuBar
            PopoverView(state: state)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .offset(x: iconX - 170, y: 36)
            ClipPreviewView(model: preview, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)  // where the app puts it: bottom-right corner
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.06, green: 0.07, blue: 0.2), Color(red: 0.25, green: 0.1, blue: 0.32), Color(red: 0.55, green: 0.2, blue: 0.22)]
                           : [Color(red: 0.62, green: 0.75, blue: 0.98), Color(red: 0.86, green: 0.72, blue: 0.95), Color(red: 1, green: 0.8, blue: 0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft glows (blur effects don't render off-screen, gradients do).
            RadialGradient(colors: [dark ? Color(red: 0.95, green: 0.4, blue: 0.3).opacity(0.45) : Color.white.opacity(0.6), .clear],
                           center: UnitPoint(x: 0.2, y: 0.8), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [dark ? Color(red: 0.3, green: 0.4, blue: 1).opacity(0.4) : Color(red: 0.5, green: 0.6, blue: 1).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.8, y: 0.15), startRadius: 0, endRadius: 480)
        }
    }

    private var menuBar: some View {
        let ink: Color = dark ? .white : .black
        return HStack(spacing: 0) {
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 14))
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["Plik", "Edycja", "Widok", "Idź", "Okno", "Pomoc"], id: \.self) { Text($0).font(.system(size: 13)) }
            }
            .padding(.leading, 20)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.18)).frame(width: 32, height: 22)
                Image(nsImage: MenuBarIcon.image(.idle, darkMenuBar: dark)).renderingMode(.template)
            }
            .frame(width: 36)
            ForEach(["magnifyingglass", "wifi", "battery.75percent", "switch.2"], id: \.self) {
                Image(systemName: $0).font(.system(size: 13)).frame(width: 28)
            }
            Text(Date().formatted(.dateTime.locale(Locale(identifier: "pl_PL")).weekday(.abbreviated).day().month(.abbreviated).hour().minute())).font(.system(size: 13)).frame(width: 130, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .foregroundStyle(ink)
        .frame(height: 28)
        .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.35))
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
