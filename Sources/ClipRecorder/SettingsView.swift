import SwiftUI

/// Settings window in the style of macOS System Settings: translucent sidebar
/// with colored icons, section title inside the content, native grouped forms.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, account, recording, audio, shortcuts, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "Ogólne"
            case .account: return "Konto"
            case .recording: return "Nagrywanie"
            case .audio: return "Dźwięk"
            case .shortcuts: return "Skróty"
            case .privacy: return "Prywatność"
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
                    Text("Wersja \(Self.version)")
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
        window.title = "Ustawienia ClipRecorder"
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
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                Toggle("Efekty dźwiękowe", isOn: $state.soundsEnabled)
                Toggle("Pokazuj podgląd po zapisie", isOn: $state.showPreview)
                Toggle("Sprawdzaj aktualizacje", isOn: $state.checkForUpdates)
            }
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(state.clipsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Zmień…", action: state.chooseClipsDirectory)
                        Button("Pokaż", action: state.openClipsFolder)
                    }
                }
                Picker("Usuwaj klipy starsze niż", selection: $state.cleanupDays) {
                    Text("Nigdy").tag(0)
                    Text("7 dni").tag(7)
                    Text("30 dni").tag(30)
                    Text("90 dni").tag(90)
                }
                Picker("Usuwaj, gdy folder przekroczy", selection: $state.cleanupGB) {
                    Text("Bez limitu").tag(0)
                    Text("10 GB").tag(10)
                    Text("20 GB").tag(20)
                    Text("50 GB").tag(50)
                    Text("100 GB").tag(100)
                }
            } header: {
                Text("Klipy")
            } footer: {
                Text("Stare klipy trafiają do Kosza, więc da się je odzyskać.")
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
                        Button("Moje klipy") { cloud.openDashboard() }
                        Button("Wyloguj") { cloud.signOut() }
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
                            Text("Dokończ logowanie w przeglądarce").font(.headline)
                            Text("Sprawdź, czy strona pokazuje ten sam kod.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(login.userCode)
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Spacer()
                        Button("Otwórz stronę", action: cloud.reopenLoginPage)
                        Button("Anuluj", action: cloud.cancelLogin)
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(onColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Udostępniaj klipy linkiem").font(.headline)
                            Text("Logujesz się w przeglądarce. Aplikacja nie zna Twojego hasła.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Button("Załóż konto…") { cloud.openSignUp() }
                        Spacer()
                        Button("Zaloguj się") { cloud.startLogin() }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                    }
                }
            } header: {
                Text("Konto")
            }

            Section {
                Picker("Kto widzi nowe klipy", selection: $cloud.visibility) {
                    ForEach(CloudService.Visibility.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Udostępniaj każdy nowy klip", isOn: $cloud.autoShare)
            } header: {
                Text("Udostępnianie")
            } footer: {
                Text("Klip trafia na Twoje konto, a link do schowka. Na Discordzie czy Messengerze link pokaże odtwarzacz. Tytuł i widoczność zmienisz później na stronie.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                LabeledContent("Serwer") {
                    if editingServer.value {
                        HStack {
                            TextField("", text: $serverDraft.text, prompt: Text(CloudService.defaultServer))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 240)
                                .onSubmit(commitServer)
                            Button("Zapisz", action: commitServer)
                        }
                    } else {
                        HStack {
                            Text(cloud.server).foregroundStyle(.secondary)
                            Button("Zmień") {
                                serverDraft.text = cloud.server
                                editingServer.value = true
                            }
                        }
                    }
                }
                if cloud.server != CloudService.defaultServer {
                    Button("Przywróć \(CloudService.defaultServer)") {
                        cloud.server = CloudService.defaultServer
                        editingServer.value = false
                    }
                }
            } header: {
                Text("Zaawansowane")
            } footer: {
                Text("Zmieniaj tylko, jeśli masz własny serwer. Zmiana wyloguje Cię.")
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
                Text("\(bytes(quota.usage.bytes)) z \(bytes(quota.plan.storageBytes))"
                     + (quota.plan.uploadsPerDay > 0 ? " · dziś \(quota.usage.uploadsToday)/\(quota.plan.uploadsPerDay)" : ""))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Plan \(quota.plan.name)")
                    Button("Plany…", action: openPricing).buttonStyle(.link).font(.caption)
                }
                Text("Klipy do \(bytes(quota.plan.maxClipBytes))"
                     + (quota.plan.expiresAt.map { " · ważny do \(Date(timeIntervalSince1970: $0 / 1000).formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
                Picker("Źródło", selection: $state.source) {
                    Text("Główny ekran").tag(CaptureSettings.Source.mainDisplay)
                    ForEach(state.displays, id: \.id) { display in
                        Text(display.name).tag(CaptureSettings.Source.display(display.id))
                    }
                    Divider()
                    ForEach(appChoices, id: \.id) { app in
                        Text("Okno: \(app.name)").tag(CaptureSettings.Source.app(bundleID: app.id, name: app.name))
                    }
                }
                Picker("Rozdzielczość", selection: $state.maxHeight) {
                    Text("Pełna").tag(0)
                    Text("1440p").tag(1440)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                }
                Picker("Płynność", selection: $state.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Picker("Jakość", selection: $state.quality) {
                    ForEach(CaptureSettings.Quality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Przy nagrywaniu okna liczy się największe okno aplikacji. Zmiana tych ustawień kasuje to, co już nagrano w tle.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                Picker("Pamiętaj ostatnie", selection: $state.bufferSeconds) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                }
            } footer: {
                Text(state.bufferSeconds > CaptureSettings.maxRAMBufferSeconds
                     ? "Ponad 2 minuty trzymane są na dysku, żeby nie zajmowały pamięci. To ciągły zapis około \(estimate) na minutę."
                     : "Nagranie jest trzymane w pamięci, około \(estimate) na minutę.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section("Oszczędzanie energii") {
                Toggle("Wstrzymuj na baterii", isOn: $state.pauseOnBattery)
                Toggle("Wstrzymuj w trybie oszczędzania energii", isOn: $state.pauseOnLowPower)
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
            Section("Co nagrywać") {
                Toggle("Dźwięk komputera", isOn: $state.includeSystemAudio)
                Toggle("Mikrofon", isOn: $state.includeMic)
                Picker("Który mikrofon", selection: $state.micSelection) {
                    Text("Automatycznie").tag(Microphones.auto)
                    Divider()
                    ForEach(state.microphones) { mic in
                        Text(mic.isBluetooth ? "\(mic.name) – Bluetooth" : mic.name).tag(mic.id)
                    }
                }
                .disabled(!state.includeMic)
                if state.includeMic, state.activeMic?.isBluetooth == true {
                    Label("Mikrofon w słuchawkach Bluetooth pogarsza jakość muzyki.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Dźwięk komputera") {
                    HStack {
                        Slider(value: $state.mixSystemVolume, in: 0...1)
                        Text("\(Int(state.mixSystemVolume * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Mikrofon") {
                    HStack {
                        Slider(value: $state.mixMicVolume, in: 0...1)
                        Text("\(Int(state.mixMicVolume * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Chroń przed przesterowaniem", isOn: $state.limiter)
            } header: {
                Text("Głośność w klipie")
            } footer: {
                Text("Tak brzmi klip przy odtwarzaniu i po udostępnieniu linkiem. Osobne nagrania komputera i mikrofonu zostają bez zmian. Jeśli gra zagłusza głos, ścisz dźwięk komputera.")
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
                row(.toggleClip, "Nagraj", "Zapisuje ostatnie \(state.bufferLabel) i nagrywa dalej. Drugie naciśnięcie kończy.")
                row(.instantClip, "Zapisz", "Od razu zapisuje ostatnie \(state.bufferLabel).")
                row(.marker, "Znacznik", "Zaznacza ważny moment podczas nagrywania.")
            } footer: {
                Text("Kliknij skrót i naciśnij nowe klawisze. ⌫ usuwa, Esc anuluje. Skróty działają wszędzie, także w grach.")
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
                Text("Automatyzacja")
            } footer: {
                Text("Te adresy działają w aplikacji Skróty, na Stream Decku i w Terminalu. Kliknij adres, aby go skopiować.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }

    private static let automation: [(title: String, url: String)] = [
        ("Zapisz ostatnie sekundy", "cliprecorder://save"),
        ("Nagraj / zatrzymaj", "cliprecorder://record"),
        ("Dodaj znacznik", "cliprecorder://marker"),
        ("Wstrzymaj / wznów", "cliprecorder://pause"),
    ]

    private func row(_ action: HotKeyCenter.Action, _ title: String, _ detail: String) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                KeyRecorder(combo: Binding(get: { state.combo(for: action) }, set: { state.setCombo($0, for: action) }))
                if state.hotKeyConflicts.contains(action) {
                    Text("Zajęty przez inną aplikację").font(.caption).foregroundStyle(.red)
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
                Text("Ukryj w nagraniu")
            } footer: {
                Text("Okna zaznaczonych aplikacji nie pojawią się w klipach. Lista pokazuje uruchomione aplikacje.")
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
        .help("Kliknij, aby skopiować")
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
                        Text("Naciśnij skrót…").foregroundStyle(accent)
                    }
                } else if let combo {
                    KeyCaps(keys: combo.keys)
                } else {
                    Text("Ustaw skrót").foregroundStyle(.secondary)
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
