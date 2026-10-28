import SwiftUI

/// Settings window in the style of macOS System Settings: translucent sidebar
/// with colored icons, section title inside the content, native grouped forms.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, account, recording, audio, shortcuts, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .account: return String(localized: "Account")
            case .recording: return String(localized: "Recording")
            case .audio: return String(localized: "Audio")
            case .shortcuts: return String(localized: "Shortcuts")
            case .privacy: return String(localized: "Privacy")
            }
        }
        var color: Color {
            switch self {
            case .general: return .gray
            case .account: return .teal
            case .recording: return accent
            case .audio: return onColor
            case .shortcuts: return .indigo
            case .privacy: return .blue
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .account: return "link"
            case .recording: return "record.circle"
            case .audio: return "waveform"
            case .shortcuts: return "keyboard"
            case .privacy: return "eye.slash"
            }
        }
    }

    final class Navigation: ObservableObject {
        @Published var section: Section
        init(_ section: Section) { self.section = section }
    }

    @ObservedObject var state: AppState
    /// Owned by the window's creator, so it can switch sections of an open window.
    @ObservedObject var nav: Navigation
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // System Settings–style sidebar: translucent, colored icons, sliding highlight.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { section in
                SidebarRow(section: section, isSelected: nav.section == section, namespace: selection) {
                    withAnimation(snappy) { nav.section = section }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ClipRecorder").font(.caption.weight(.semibold))
                    Text("Version \(Self.version)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .padding(.top, 52)  // room for the traffic lights
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(VisualEffect(material: .sidebar))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(nav.section.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .frame(height: 52, alignment: .bottom)
            Group {
                switch nav.section {
                case .general: GeneralSettings(state: state)
                case .account: AccountSettings(state: state, cloud: state.cloud)
                case .recording: RecordingSettings(state: state)
                case .audio: AudioSettings(state: state)
                case .shortcuts: ShortcutSettings(state: state)
                case .privacy: PrivacySettings(state: state)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .id(nav.section)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(snappy, value: nav.section)
    }

    /// Creates the settings window (borderless-looking title bar, content under it).
    @MainActor
    /// Overridden by snapshots, which run outside the app bundle.
    static var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    static func makeWindow(state: AppState, section: Section = .general) -> NSWindow {
        makeWindow(state: state, nav: Navigation(section))
    }

    static func makeWindow(state: AppState, nav: Navigation) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: SettingsView(state: state, nav: nav))
        window.title = String(localized: "ClipRecorder Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private struct SidebarRow: View {
    let section: SettingsView.Section
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(section.color.gradient))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hover.value {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover.value = h } }
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Sections

private struct GeneralSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                Toggle("Sound effects", isOn: $state.soundsEnabled)
                Toggle("Show preview after saving", isOn: $state.showPreview)
                Toggle("Check for updates", isOn: $state.checkForUpdates)
            }
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(state.clipsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Change…", action: state.chooseClipsDirectory)
                        Button("Show", action: state.openClipsFolder)
                    }
                }
                Picker("Delete clips older than", selection: $state.cleanupDays) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Picker("Delete when folder exceeds", selection: $state.cleanupGB) {
                    Text("No limit").tag(0)
                    Text("10 GB").tag(10)
                    Text("20 GB").tag(20)
                    Text("50 GB").tag(50)
                    Text("100 GB").tag(100)
                }
            } header: {
                Text("Clips")
            } footer: {
                Text("Old clips go to the Trash, so you can still get them back.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }
}

private struct AccountSettings: View {
    @ObservedObject var state: AppState
    @ObservedObject var cloud: CloudService
    @StateObject private var editingServer = Flag()
    @StateObject private var serverDraft = TextDraft()

    var body: some View {
        Form {
            Section {
                if let account = cloud.account {
                    HStack(spacing: 12) {
                        Text(initials(account.name.isEmpty ? account.email : account.name))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name.isEmpty ? account.username : account.name).font(.headline)
                            Text("\(account.email) · @\(account.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("My clips") { cloud.openDashboard() }
                        Button("Sign out") { cloud.signOut() }
                    }
                    .padding(.vertical, 4)
                    .transition(.opacity)
                    if let quota = cloud.quota {
                        QuotaRow(quota: quota, openPricing: cloud.openPricing)
                    }
                } else if let login = cloud.pendingLogin {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Finish signing in in your browser").font(.headline)
                            Text("Make sure the page shows the same code.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(login.userCode)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button("Open page", action: cloud.reopenLoginPage)
                        Button("Cancel", action: cloud.cancelLogin)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(onColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share clips by link").font(.headline)
                            Text("You sign in in your browser. The app never sees your password.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Button("Create account…") { cloud.openSignUp() }
                        Spacer()
                        Button(String(localized: "settings.sign-in", defaultValue: "Sign in")) { cloud.startLogin() }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                    }
                }
            } header: {
                Text("Account")
            }

            Section {
                Picker("Who can see new clips", selection: $cloud.visibility) {
                    ForEach(CloudService.Visibility.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Share every new clip", isOn: $cloud.autoShare)
            } header: {
                Text("Sharing")
            } footer: {
                Text("The clip goes to your account and the link to your clipboard. On Discord or Messenger the link shows a player. You can change the title and visibility later on the website.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                LabeledContent("Server") {
                    if editingServer.value {
                        HStack {
                            TextField("", text: $serverDraft.text, prompt: Text(CloudService.defaultServer))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                                .onSubmit(commitServer)
                            Button("Save", action: commitServer)
                        }
                    } else {
                        HStack {
                            Text(cloud.server).foregroundStyle(.secondary)
                            Button("Change") {
                                serverDraft.text = cloud.server
                                editingServer.value = true
                            }
                        }
                    }
                }
                if cloud.server != CloudService.defaultServer {
                    Button("Restore \(CloudService.defaultServer)") {
                        cloud.server = CloudService.defaultServer
                        editingServer.value = false
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Only change this if you run your own server. Changing it signs you out.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
        .animation(snappy, value: cloud.account)
        .animation(snappy, value: cloud.pendingLogin)
    }

    private func commitServer() {
        let value = serverDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value != cloud.server { cloud.server = value }
        editingServer.value = false
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

private struct QuotaRow: View {
    let quota: CloudService.Quota
    let openPricing: () -> Void

    var body: some View {
        let used = Double(quota.usage.bytes)
        let total = Double(max(quota.plan.storageBytes, 1))
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                // Drawn by hand: the system bar turns grey whenever the window isn't key.
                Capsule().fill(.primary.opacity(0.1))
                    .overlay(alignment: .leading) {
                        Capsule().fill(used / total > 0.9 ? accent : onColor)
                            .frame(width: max(6, 220 * min(used / total, 1)))
                    }
                    .frame(width: 220, height: 6)
                Text(usage)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "\(quota.plan.name) plan"))
                    Button("Plans…", action: openPricing).buttonStyle(.link).font(.caption)
                }
                Text(limits)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "1.24 GB of 5 GB · today 3/50"
    private var usage: String {
        let used = bytes(quota.usage.bytes), total = bytes(quota.plan.storageBytes)
        var parts = [String(localized: "\(used) of \(total)")]
        if quota.plan.uploadsPerDay > 0 {
            let today = "\(quota.usage.uploadsToday)/\(quota.plan.uploadsPerDay)"
            parts.append(String(localized: "today \(today)"))
        }
        return parts.joined(separator: " · ")
    }

    /// "Clips up to 500 MB · valid until Dec 1, 2026"
    private var limits: String {
        let size = bytes(quota.plan.maxClipBytes)
        var parts = [String(localized: "Clips up to \(size)")]
        if let expires = quota.plan.expiresAt {
            let date = Date(timeIntervalSince1970: expires / 1000).formatted(date: .abbreviated, time: .omitted)
            parts.append(String(localized: "valid until \(date)"))
        }
        return parts.joined(separator: " · ")
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private struct RecordingSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Source", selection: $state.source) {
                    Text("Main display").tag(CaptureSettings.Source.mainDisplay)
                    ForEach(state.displays, id: \.id) { display in
                        Text(display.name).tag(CaptureSettings.Source.display(display.id))
                    }
                    Divider()
                    ForEach(appChoices, id: \.id) { app in
                        Text("Window: \(app.name)").tag(CaptureSettings.Source.app(bundleID: app.id, name: app.name))
                    }
                }
                Picker("Resolution", selection: $state.maxHeight) {
                    Text("Native").tag(0)
                    Text("1440p").tag(1440)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                }
                Picker("Frame rate", selection: $state.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Picker("Quality", selection: $state.quality) {
                    ForEach(CaptureSettings.Quality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("When recording a window, the app’s largest window is used. Changing these settings clears what’s already been recorded in the background.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                Picker("Keep last", selection: $state.bufferSeconds) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                }
            } footer: {
                Text(state.bufferSeconds > CaptureSettings.maxRAMBufferSeconds
                     ? String(localized: "Over 2 minutes are kept on disk so they don’t take up memory. That’s a constant write of about \(estimate) per minute.")
                     : String(localized: "The recording is kept in memory, about \(estimate) per minute."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section("Power saving") {
                Toggle("Pause on battery", isOn: $state.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $state.pauseOnLowPower)
            }
        }
    }

    private var appChoices: [AppState.AppChoice] {
        var apps = state.runningApps
        if case .app(let id, let name) = state.source, !apps.contains(where: { $0.id == id }) {
            apps.insert(AppState.AppChoice(id: id, name: name, icon: nil), at: 0)
        }
        return apps
    }

    /// Rough data rate of the buffer (HEVC + PCM audio).
    private var estimate: String {
        let height = Double(state.maxHeight > 0 ? state.maxHeight : 1800)
        let pixels = height * height * 16 / 10
        let video = min(max(pixels * Double(state.fps) * state.quality.bitsPerPixel, 3_000_000), 50_000_000)
        let audio = 48_000.0 * 4 * 3 * 8  // system stereo + mic, float32
        let mbPerMinute = (video + audio) / 8 * 60 / 1_000_000
        return String(format: "%.0f MB", mbPerMinute)
    }
}

private struct AudioSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("What to record") {
                Toggle("System audio", isOn: $state.includeSystemAudio)
                Toggle("Microphone", isOn: $state.includeMic)
                Picker("Which microphone", selection: $state.micSelection) {
                    Text("Automatic").tag(Microphones.auto)
                    Divider()
                    ForEach(state.microphones) { mic in
                        Text(mic.isBluetooth ? "\(mic.name) – Bluetooth" : mic.name).tag(mic.id)
                    }
                }
                .disabled(!state.includeMic)
                if state.includeMic, state.activeMic?.isBluetooth == true {
                    Label("A Bluetooth headset mic lowers music quality.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("System audio") {
                    HStack {
                        Slider(value: $state.mixSystemVolume, in: 0...1)
                        Text("\(Int(state.mixSystemVolume * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Microphone") {
                    HStack {
                        Slider(value: $state.mixMicVolume, in: 0...1)
                        Text("\(Int(state.mixMicVolume * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Prevent distortion", isOn: $state.limiter)
            } header: {
                Text("Clip volume")
            } footer: {
                Text("This is how the clip sounds when played and when shared by link. The separate system audio and microphone tracks stay unchanged. If a game drowns out your voice, turn down the system audio.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                row(.toggleClip, String(localized: "Record"),
                    String(localized: "Saves the last \(state.bufferLabel) and keeps recording. Press again to stop."))
                row(.instantClip, String(localized: "Save"), String(localized: "Saves the last \(state.bufferLabel) right away."))
                row(.marker, String(localized: "Marker"), String(localized: "Marks an important moment while recording."))
            } footer: {
                Text("Click a shortcut and press the new keys. ⌫ clears it, Esc cancels. Shortcuts work everywhere, games included.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                ForEach(Self.automation, id: \.url) { item in
                    LabeledContent(item.title) {
                        CopyableCode(text: item.url)
                    }
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("These URLs work in the Shortcuts app, on a Stream Deck and in Terminal. Click a URL to copy it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }

    private static let automation: [(title: String, url: String)] = [
        (String(localized: "Save the last seconds"), "cliprecorder://save"),
        (String(localized: "Record / stop"), "cliprecorder://record"),
        (String(localized: "Add marker"), "cliprecorder://marker"),
        (String(localized: "Pause / resume"), "cliprecorder://pause"),
    ]

    private func row(_ action: HotKeyCenter.Action, _ title: String, _ detail: String) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                KeyRecorder(combo: Binding(get: { state.combo(for: action) }, set: { state.setCombo($0, for: action) }))
                if state.hotKeyConflicts.contains(action) {
                    Text("Used by another app").font(.caption).foregroundStyle(.red)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(apps, id: \.id) { app in
                    Toggle(isOn: binding(for: app.id)) {
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 18, height: 18)
                            }
                            Text(app.name)
                        }
                    }
                }
            } header: {
                Text("Hide from recordings")
            } footer: {
                Text("Windows of the selected apps won’t appear in clips. The list shows running apps.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }

    private var apps: [AppState.AppChoice] {
        var apps = state.runningApps
        // Excluded apps that aren't running: look up their real name and icon.
        for id in state.excludedBundleIDs where !apps.contains(where: { $0.id == id }) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                apps.append(AppState.AppChoice(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path)))
            } else {
                apps.append(AppState.AppChoice(id: id, name: id, icon: nil))
            }
        }
        return apps
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { state.excludedBundleIDs.contains(id) },
            set: { on in
                if on { state.excludedBundleIDs.append(id) } else { state.excludedBundleIDs.removeAll { $0 == id } }
            })
    }
}

/// Monospaced snippet that copies itself on click.
private struct CopyableCode: View {
    let text: String
    @StateObject private var copied = Flag()

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(snappy) { copied.value = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(snappy) { copied.value = false }
            }
        } label: {
            HStack(spacing: 5) {
                Text(text).font(.system(size: 11, design: .monospaced))
                Image(systemName: copied.value ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copied.value ? onColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("Click to copy")
    }
}

// MARK: - Key recorder

/// Click, then press a key combination. ⌫ clears, Esc cancels.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var isRecording = false
        private var monitor: Any?
        private var resignObserver: Any?
        /// Only one recorder listens at a time.
        private static weak var active: Model?

        func start(_ onCombo: @escaping (KeyCombo?) -> Void) {
            stop()
            if let other = Self.active, other !== self { other.stop() }
            Self.active = self
            isRecording = true
            HotKeyCenter.shared.suspend()
            // Clicking away must not leave the global shortcuts switched off.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch Int(event.keyCode) {
                case 53:  // Esc
                    self.stop()
                case 51, 117:  // Delete / Forward delete
                    onCombo(nil)
                    self.stop()
                default:
                    if let combo = KeyCombo(event: event) {
                        onCombo(combo)
                        self.stop()
                    } else {
                        NSSound.beep()
                    }
                }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
            let wasRecording = isRecording
            isRecording = false
            if wasRecording { HotKeyCenter.shared.resume() }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if isRecording { HotKeyCenter.shared.resume() }
        }
    }

    var body: some View {
        Button {
            if model.isRecording { model.stop() } else { model.start { combo = $0 } }
        } label: {
            Group {
                if model.isRecording {
                    HStack(spacing: 6) {
                        PulsingDot(size: 7)
                        Text("Press shortcut…").foregroundStyle(accent)
                    }
                } else if let combo {
                    KeyCaps(keys: combo.keys)
                } else {
                    Text("Set shortcut").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 120, minHeight: 28)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.isRecording ? accent : Color.primary.opacity(0.12),
                                                                   lineWidth: model.isRecording ? 1.5 : 1))
            .animation(snappy, value: model.isRecording)
        }
        .buttonStyle(.plain)
        .onDisappear { model.stop() }
    }
}
