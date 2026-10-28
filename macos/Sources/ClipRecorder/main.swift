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
    private let settingsNav = SettingsView.Navigation(.general)
    private lazy var preview = ClipPreviewController(state: state)
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageLeading

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(state: state))

        state.onClipReady = { [weak self] url in self?.preview.show(url) }
        state.onOpenSettings = { [weak self] section in self?.showSettings(section) }

        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshChrome() }
            .store(in: &cancellables)
        refreshChrome()

        state.start()
    }

    /// Automation (Shortcuts, Stream Deck, scripts): `open cliprecorder://save` etc.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "cliprecorder" {
            switch url.host() ?? url.path() {
            case "save": state.saveInstantClip()
            case "record", "toggle": state.toggleClip()
            case "stop": if state.isRecording { state.toggleClip() }
            case "marker": state.addMarker()
            case "pause": state.togglePause()
            case "resume": state.resume()
            case "open-last": if let last = state.recentClips.first { state.open(last) }
            case "settings": showSettings()
            default: NSLog("ClipRecorder: unknown URL \(url)")
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.needsQuitConfirmation else { return .terminateNow }
        // Save the running clip first instead of leaving a broken file behind.
        state.prepareToQuit { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    /// Right-click menu: the common actions without opening the popover.
    private func showQuickMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String? = nil, enabled: Bool = true, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, action: action)
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            item.isEnabled = enabled
            menu.addItem(item)
        }
        let ready = state.status == .buffering
        if state.isRecording {
            add(String(localized: "Stop and save"), "stop.fill") { [state] in state.toggleClip() }
            add(String(localized: "Add marker"), "bookmark.fill") { [state] in state.addMarker() }
        } else {
            add(String(localized: "Record from \(state.bufferLabel) ago"), "record.circle", enabled: ready) { [state] in state.toggleClip() }
            add(String(localized: "Save last \(state.bufferLabel)"), "bolt.fill", enabled: ready) { [state] in state.saveInstantClip() }
        }
        menu.addItem(.separator())
        if let last = state.recentClips.first {
            add(String(localized: "Open last clip"), "play.rectangle") { [state] in state.open(last) }
        }
        add(String(localized: "Show clips folder"), "folder") { [state] in state.openClipsFolder() }
        menu.addItem(.separator())
        if state.userPaused {
            add(String(localized: "Resume background recording"), "play.fill") { [state] in state.resume() }
        } else {
            let pause = NSMenuItem(title: String(localized: "Pause"), action: nil, keyEquivalent: "")
            pause.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: nil)
            pause.isEnabled = !state.isRecording
            let sub = NSMenu()
            for (title, duration) in [(String(localized: "For 15 minutes"), 15.0 * 60), (String(localized: "For 1 hour"), 3600),
                                      (String(localized: "Until resumed"), -1)] {
                sub.addItem(ClosureMenuItem(title: title) { [state] in state.pause(for: duration < 0 ? nil : duration) })
            }
            pause.submenu = sub
            menu.addItem(pause)
        }
        add(String(localized: "Settings…"), "gearshape") { [weak self] in self?.showSettings() }
        menu.addItem(.separator())
        add(String(localized: "Quit ClipRecorder")) { NSApp.terminate(nil) }

        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.performClick(nil)  // opens the menu at the right spot
        statusItem.menu = nil                 // left click keeps opening the popover
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

    private func showSettings(_ section: SettingsView.Section? = nil) {
        popover.performClose(nil)
        if let section {
            if settingsWindow == nil { settingsNav.section = section } else { withAnimation(snappy) { settingsNav.section = section } }
        }
        if settingsWindow == nil {
            settingsWindow = SettingsView.makeWindow(state: state, nav: settingsNav)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private var iconKey = ""

    private func refreshChrome() {
        guard let button = statusItem.button else { return }
        // Called on every state change (twice a second while recording) – only redraw when needed.
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key: String
        switch state.status {
        case .failed: key = "failed"
        case .recording: key = dark ? "recording-dark" : "recording"
        case .paused: key = "paused"
        default: key = "idle"
        }
        if key != iconKey {
            iconKey = key
            switch state.status {
            case .failed:
                let image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "ClipRecorder")
                image?.isTemplate = true
                button.image = image
            case .recording: button.image = MenuBarIcon.image(.recording, darkMenuBar: dark)
            case .paused: button.image = MenuBarIcon.image(.paused)
            default: button.image = MenuBarIcon.image(.idle)
            }
            button.contentTintColor = nil
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let title = state.isRecording ? " \(formatDuration(state.elapsed))" : ""
        if button.title != title { button.title = title }
        button.toolTip = tooltip

        if state.isRecording { showHUD() } else { hideHUD() }
    }

    private var tooltip: String {
        switch state.status {
        case .starting: return String(localized: "ClipRecorder – starting")
        case .buffering: return String(localized: "ClipRecorder – ready, keeping the last \(state.bufferLabel)")
        case .recording: return String(localized: "ClipRecorder – recording")
        case .paused(let reason): return "ClipRecorder – \(reason.lowercased())"
        case .failed: return String(localized: "ClipRecorder – permission needed")
        }
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

/// Menu item that runs a closure (keeps the quick menu code short).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
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
