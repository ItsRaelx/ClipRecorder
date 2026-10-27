import SwiftUI

/// Settings window: sidebar with sections (like Whereby/Zoom settings),
/// native grouped forms on the right.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, recording, audio, shortcuts, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "Ogólne"
            case .recording: return "Nagrywanie"
            case .audio: return "Dźwięk"
            case .shortcuts: return "Skróty"
            case .privacy: return "Prywatność"
            }
        }
        var color: Color {
            switch self {
            case .general: return .gray
            case .recording: return accent
            case .audio: return onColor
            case .shortcuts: return .indigo
            case .privacy: return .blue
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .recording: return "record.circle"
            case .audio: return "waveform"
            case .shortcuts: return "keyboard"
            case .privacy: return "eye.slash"
            }
        }
    }

    final class Navigation: ObservableObject {
        @Published var section: Section?
        init(_ section: Section) { self.section = section }
    }

    @ObservedObject var state: AppState
    @StateObject private var nav: Navigation

    init(state: AppState, section: Section = .general) {
        self.state = state
        _nav = StateObject(wrappedValue: Navigation(section))
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $nav.section) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(section.color.gradient))
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Group {
                switch nav.section ?? .general {
                case .general: GeneralSettings(state: state)
                case .recording: RecordingSettings(state: state)
                case .audio: AudioSettings(state: state)
                case .shortcuts: ShortcutSettings(state: state)
                case .privacy: PrivacySettings(state: state)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((nav.section ?? .general).title)
            .id(nav.section)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(snappy, value: nav.section)
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

// MARK: - Sections

private struct GeneralSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                Toggle("Dźwięki przy starcie i zapisie klipu", isOn: $state.soundsEnabled)
                Toggle("Pokazuj podgląd po zapisaniu klipu", isOn: $state.showPreview)
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
                Picker("Gdy folder przekroczy", selection: $state.cleanupGB) {
                    Text("Bez limitu").tag(0)
                    Text("10 GB").tag(10)
                    Text("20 GB").tag(20)
                    Text("50 GB").tag(50)
                    Text("100 GB").tag(100)
                }
            } header: {
                Text("Klipy")
            } footer: {
                Text("Usuwane są najstarsze klipy – trafiają do Kosza, więc da się je jeszcze odzyskać.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
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
                    Text("Natywna").tag(0)
                    Text("1440p").tag(1440)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                }
                Picker("Klatki na sekundę", selection: $state.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Picker("Jakość", selection: $state.quality) {
                    ForEach(CaptureSettings.Quality.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Przy „Okno: …” nagrywane jest największe okno tej aplikacji. Zmiana ustawień z tej sekcji czyści bufor.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section {
                Picker("Długość bufora", selection: $state.bufferSeconds) {
                    Text("30 s").tag(30)
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                }
            } footer: {
                Text(state.bufferSeconds > CaptureSettings.maxRAMBufferSeconds
                     ? "Bufor dłuższy niż 2 min jest trzymany na dysku (w pamięci podręcznej), żeby nie zajmował gigabajtów RAM-u. Oznacza to ciągły zapis ok. \(estimate) na minutę."
                     : "Bufor jest trzymany w pamięci RAM (ok. \(estimate) na minutę).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }

            Section("Oszczędzanie energii") {
                Toggle("Wstrzymuj bufor przy zasilaniu z baterii", isOn: $state.pauseOnBattery)
                Toggle("Wstrzymuj bufor w trybie niskiego zużycia energii", isOn: $state.pauseOnLowPower)
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
            Section("Źródła") {
                Toggle("Dźwięk systemu (wszystko, co słychać z komputera)", isOn: $state.includeSystemAudio)
                Toggle("Mikrofon", isOn: $state.includeMic)
                Picker("Urządzenie", selection: $state.micSelection) {
                    Text("Automatycznie (omija mikrofony Bluetooth)").tag(Microphones.auto)
                    Divider()
                    ForEach(state.microphones) { mic in
                        Text(mic.isBluetooth ? "\(mic.name) – Bluetooth" : mic.name).tag(mic.id)
                    }
                }
                .disabled(!state.includeMic)
                if state.includeMic, state.activeMic?.isBluetooth == true {
                    Label("Nagrywanie z mikrofonu Bluetooth przełącza słuchawki w tryb rozmowy (mono, gorsza jakość muzyki).",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Dźwięk systemu") {
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
                Toggle("Ogranicznik (chroni miks przed przesterowaniem)", isOn: $state.limiter)
            } header: {
                Text("Ścieżka „Miks”")
            } footer: {
                Text("Dotyczy tylko zmiksowanej ścieżki (i eksportu MP4). Osobne ścieżki systemu i mikrofonu zawsze zostają nietknięte. Jeśli gra zagłusza głos, ścisz dźwięk systemu.")
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
                row(.toggleClip, "Klip", "Zapisuje ostatnie \(state.bufferLabel) i nagrywa dalej; drugie naciśnięcie kończy.")
                row(.instantClip, "Szybki zapis", "Od razu zapisuje ostatnie \(state.bufferLabel), bez dalszego nagrywania.")
                row(.marker, "Znacznik", "W trakcie nagrywania dodaje rozdział – widać go w QuickTime i edytorach.")
            } footer: {
                Text("Kliknij skrót i naciśnij nową kombinację. ⌫ usuwa skrót, Esc anuluje. Skróty działają globalnie, także w grach i pełnym ekranie.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }

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
                Text("Ukrywaj okna tych aplikacji w nagraniu")
            } footer: {
                Text("Wybrane aplikacje są niewidoczne w klipach (w ich miejscu widać tło). Działa przy nagrywaniu ekranu. Okna ClipRecorder nigdy nie są nagrywane. Lista pokazuje uruchomione aplikacje.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
        }
    }

    private var apps: [AppState.AppChoice] {
        var apps = state.runningApps
        for id in state.excludedBundleIDs where !apps.contains(where: { $0.id == id }) {
            apps.append(AppState.AppChoice(id: id, name: id, icon: nil))
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

// MARK: - Key recorder

/// Click, then press a key combination. ⌫ clears, Esc cancels.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var isRecording = false
        private var monitor: Any?

        func start(_ onCombo: @escaping (KeyCombo?) -> Void) {
            stop()
            isRecording = true
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
            isRecording = false
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
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
    }
}
