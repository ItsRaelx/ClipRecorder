import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var hud: NSPanel?
    private var settingsWindow: NSWindow?
    private lazy var preview = ClipPreviewController(state: state)
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(state: state))

        state.onClipReady = { [weak self] url in self?.preview.show(url) }
        state.onOpenSettings = { [weak self] in self?.showSettings() }

        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshChrome() }
            .store(in: &cancellables)
        refreshChrome()

        state.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
            window.title = "Ustawienia ClipRecorder"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 720, height: 540))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshChrome() {
        guard let button = statusItem.button else { return }
        switch state.status {
        case .failed:
            let image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "ClipRecorder")
            image?.isTemplate = true
            button.image = image
        case .recording:
            let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            button.image = MenuBarIcon.image(.recording, darkMenuBar: dark)
        case .paused:
            button.image = MenuBarIcon.image(.paused)
        default:
            button.image = MenuBarIcon.image(.idle)
        }
        button.contentTintColor = nil
        button.title = state.isRecording ? " \(formatDuration(state.elapsed))" : ""
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        if state.isRecording { showHUD() } else { hideHUD() }
    }

    private func showHUD() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        if hud == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: RecordingHUD(state: state))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.sharingType = .none  // extra guarantee it never shows up in captures
            guard let size = panel.contentView?.fittingSize else { return }
            // Drop in from above.
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height + 24,
                                  width: size.width, height: size.height), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            hud = panel
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.3, 0.4, 1)  // slight overshoot
                panel.animator().alphaValue = 1
                panel.animator().setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                                                 width: size.width, height: size.height), display: true)
            }
            return
        }
        // Re-center: the bar grows when markers are added.
        guard let hud, let size = hud.contentView?.fittingSize, abs(hud.frame.width - size.width) > 0.5 else { return }
        hud.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                            width: size.width, height: size.height), display: true, animate: true)
    }

    private func hideHUD() {
        guard let panel = hud else { return }
        hud = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY + 20))
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

MainActor.assumeIsolated {
    // Dev helper: `ClipRecorder --snapshot <dir>` renders the popover to PNGs and exits.
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
        Snapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
