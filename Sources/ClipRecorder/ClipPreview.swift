import AVFoundation
import AVKit
import SwiftUI

/// Floating card shown in the corner after a clip is saved (macOS-screenshot
/// behaviour, Substack's "upload complete" toast look): drag it anywhere, share,
/// trim, delete. Slides in from the right and hides itself after a few seconds
/// (Canva-style countdown line), unless hovered.
@MainActor
final class ClipPreviewController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    let model = ClipPreviewModel()
    private let state: AppState
    static let visibleSeconds = 8.0

    init(state: AppState) {
        self.state = state
        model.onHoverChange = { [weak self] hovering in
            if hovering { self?.hideTask?.cancel() } else { self?.scheduleHide() }
        }
        model.onClose = { [weak self] in self?.hide() }
    }

    func show(_ url: URL) {
        model.load(url)
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: ClipPreviewView(model: model, state: state))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main, let size = panel.contentView?.fittingSize else { return }
        let visible = screen.visibleFrame
        let target = NSRect(x: visible.maxX - size.width - 4, y: visible.minY + 4, width: size.width, height: size.height)
        if !panel.isVisible {
            panel.setFrame(target.offsetBy(dx: size.width * 0.6, dy: 0), display: false)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.2, 0.35, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX + 60, y: panel.frame.minY))
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func scheduleHide() {
        hideTask?.cancel()
        model.startCountdown(Self.visibleSeconds)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled, let self else { return }
            // Keep it up while an export of this clip is running.
            if let url = self.model.url, self.state.shares[url] != nil {
                self.scheduleHide()
                return
            }
            self.hide()
        }
    }
}

@MainActor
final class ClipPreviewModel: ObservableObject {
    @Published var url: URL?
    @Published var thumbnail: NSImage?
    @Published var duration: Double = 0
    @Published var fileSize: Int = 0
    /// 1 → 0 while the card counts down to hiding itself.
    @Published var remaining: Double = 1
    @Published var appeared = false
    var onHoverChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    func load(_ url: URL) {
        self.url = url
        thumbnail = nil
        appeared = false
        fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        Task {
            let asset = AVURLAsset(url: url)
            duration = (try? await asset.load(.duration).seconds) ?? 0
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            let time = CMTime(seconds: max(0, duration - 1), preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image {
                withAnimation(.easeOut(duration: 0.25)) {
                    thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                }
            }
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.15)) { appeared = true }
    }

    func startCountdown(_ seconds: Double) {
        remaining = 1
        withAnimation(.linear(duration: seconds)) { remaining = 0 }
    }

    func pauseCountdown() {
        withAnimation(.easeOut(duration: 0.2)) { remaining = 1 }
    }
}

struct ClipPreviewView: View {
    @ObservedObject var model: ClipPreviewModel
    @ObservedObject var state: AppState
    @StateObject private var hoverThumb = Flag()

    var body: some View {
        VStack(spacing: 0) {
            if let url = model.url {
                thumbnail(url)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(onColor)
                            .scaleEffect(model.appeared ? 1 : 0.3)
                            .opacity(model.appeared ? 1 : 0)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Klip zapisany").font(.system(size: 13, weight: .semibold))
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let progress = state.shares[url] {
                        ProgressRow(title: "Wysyłanie…", progress: progress,
                                    cancel: { state.cancelShare(url) })
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 8) {
                            if let login = state.cloud.pendingLogin {
                                LoginWaitingRow(code: login.userCode, reopen: state.cloud.reopenLoginPage, cancel: state.cloud.cancelLogin)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            } else if let link = state.cloud.link(for: url) {
                                LinkRow(link: link, copy: { state.copyLink(link) }, open: { NSWorkspace.shared.open(link) })
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            actions(url)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(12)
            }
            // Canva-style countdown line
            GeometryReader { geo in
                Capsule().fill(accent.opacity(0.8))
                    .frame(width: geo.size.width * model.remaining, height: 2)
            }
            .frame(height: 2)
        }
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.11)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(16)  // room for the shadow
        .environment(\.colorScheme, .dark)
        .animation(snappy, value: model.url.flatMap { state.shares[$0] } != nil)
        .animation(snappy, value: model.url.flatMap { state.cloud.link(for: $0) })
        .animation(snappy, value: state.cloud.pendingLogin)
        .onHover { hovering in
            if hovering { model.pauseCountdown() }
            model.onHoverChange?(hovering)
        }
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.fileSize), countStyle: .file)
        return "\(formatDuration(model.duration)) · \(size)"
    }

    private func thumbnail(_ url: URL) -> some View {
        ZStack {
            Group {
                if let image = model.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    LinearGradient(colors: [Color(white: 0.2), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(width: 300, height: 169)
            .clipped()
            .scaleEffect(hoverThumb.value ? 1.04 : 1)

            // Play button appears on hover
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.55)))
                .scaleEffect(hoverThumb.value ? 1 : 0.6)
                .opacity(hoverThumb.value ? 1 : 0)

            VStack {
                HStack {
                    Spacer()
                    Button { model.onClose?() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack {
                    Spacer()
                    Text(formatDuration(model.duration))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.65)))
                }
            }
            .padding(8)
        }
        .frame(width: 300, height: 169)
        .clipped()
        .contentShape(Rectangle())
        .onHover { h in withAnimation(snappy) { hoverThumb.value = h } }
        .onTapGesture { state.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help("Kliknij, aby obejrzeć. Możesz też przeciągnąć klip, gdzie chcesz.")
    }

    private func actions(_ url: URL) -> some View {
        let shared = state.cloud.link(for: url) != nil
        return HStack(spacing: 6) {
            Button { state.shareLink(url) } label: {
                Label(shared ? "Kopiuj link" : "Udostępnij link", systemImage: shared ? "doc.on.doc" : "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .help(shared ? "Skopiuj link do schowka" : "Wyślij klip i skopiuj link")
            IconButton(icon: "scissors", help: "Przytnij") { state.trim(url) }
            IconButton(icon: "folder", help: "Pokaż w Finderze") { state.reveal(url) }
            IconButton(icon: "trash", help: "Przenieś do Kosza", tint: accent) {
                state.delete(url)
                model.onClose?()
            }
        }
    }
}

private struct ProgressRow: View {
    let title: String
    let progress: Double
    var cancel: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let cancel {
                    Button(action: cancel) { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Anuluj wysyłanie")
                }
            }
            ProgressView(value: progress).tint(accent)
                .animation(.easeOut(duration: 0.2), value: progress)
        }
    }
}

/// Copied link (teal capsule, click to copy again).
struct LinkRow: View {
    let link: URL
    let copy: () -> Void
    let open: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(onColor)
            Text("\(link.host() ?? "")\(link.path())")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: open) {
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(onColor)
            .help("Otwórz w przeglądarce")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        // Radius just under half the height: a stroked full capsule renders a seam at its ends.
        .background {
            RoundedRectangle(cornerRadius: 13, style: .circular)
                .fill(onColor.opacity(hover.value ? 0.2 : 0.13))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(onColor.opacity(0.3)))
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .circular))
        .onTapGesture(perform: copy)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover.value = h } }
        .help("Kliknij, aby skopiować link")
    }
}

/// Shown while the browser login (device code) is pending.
struct LoginWaitingRow: View {
    let code: String
    let reopen: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dokończ logowanie w przeglądarce").font(.caption.weight(.semibold))
                Text("Kod: \(code)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Otwórz", action: reopen).buttonStyle(.link).font(.caption)
            Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Anuluj logowanie")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
    }
}

/// Plain button with a spring press.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(snappy, value: configuration.isPressed)
    }
}

private struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color = .white
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            IconLabel(icon: icon, tint: tint, hovering: hover.value)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(snappy) { hover.value = h } }
        .help(help)
    }
}

/// Round icon used by every small action in the preview card.
private struct IconLabel: View {
    let icon: String
    var tint: Color = .white
    var hovering = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(.white.opacity(hovering ? 0.16 : 0.08)))
            .contentShape(Circle())
            .scaleEffect(hovering ? 1.06 : 1)
    }
}

// MARK: - Trim window

/// QuickTime-style trimming (AVPlayerView's built-in trim UI).
@MainActor
final class TrimWindowController: NSObject, NSWindowDelegate {
    private static var current: TrimWindowController?

    private let window: NSWindow
    private let playerView = AVPlayerView()
    private let onTrim: (CMTimeRange) -> Void
    private var statusObservation: NSKeyValueObservation?

    static func show(_ url: URL, onTrim: @escaping (CMTimeRange) -> Void) {
        current?.window.close()
        let controller = TrimWindowController(url: url, onTrim: onTrim)
        current = controller
        controller.present()
    }

    private init(url: URL, onTrim: @escaping (CMTimeRange) -> Void) {
        self.onTrim = onTrim
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Przytnij – \(url.deletingPathExtension().lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = playerView
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: url)
    }

    private func present() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Trimming can only begin once the item is ready to play.
        statusObservation = playerView.player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { self?.beginTrimming() }
        }
    }

    private func beginTrimming() {
        statusObservation = nil
        guard playerView.canBeginTrimming else { return }
        playerView.beginTrimming { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                if result == .okButton, let item = self.playerView.player?.currentItem {
                    let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
                    let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
                    if end > start { self.onTrim(CMTimeRange(start: start, end: end)) }
                }
                self.window.close()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        if Self.current === self { Self.current = nil }
    }
}
