import SwiftUI

/// Menu bar popover. Layout follows Loom's recorder popover (source rows with
/// On/Off pills + one big action button), Whereby's recording card and
/// v0/Base44-style inline toasts. Live level meters follow Mistral/VEED.
struct PopoverView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            UpdateBanner(updater: state.updater)
            Group {
                switch state.status {
                case .failed(let text):
                    permissionCard(text).transition(.cardSwap)
                case .paused(let reason):
                    pausedCard(reason).transition(.cardSwap)
                default:
                    VStack(spacing: 14) {
                        sources
                        actionArea
                    }
                    .transition(.cardSwap)
                }
            }
            if let login = state.cloud.pendingLogin {
                LoginWaitingRow(code: login.userCode, reopen: state.cloud.reopenLoginPage, cancel: state.cloud.cancelLogin)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !state.recentClips.isEmpty { recentClips.transition(.opacity) }
            if let message = state.message {
                Toast(text: message)
                    .id(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .animation(snappy, value: state.status)
        .animation(snappy, value: state.message)
        .animation(snappy, value: state.recentClips)
        .animation(snappy, value: state.cloud.pendingLogin)
        .animation(snappy, value: state.permissionGranted)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(state.isRecording ? -360 : 0))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: state.isRecording)
            VStack(alignment: .leading, spacing: 0) {
                Text("ClipRecorder").font(.headline)
                Text(state.sourceName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        let (label, color, pulsing): (String, Color, Bool) = {
            switch state.status {
            case .starting: return ("Uruchamianie…", .secondary, true)
            case .buffering: return ("Gotowy", onColor, true)
            case .recording: return ("Nagrywanie", accent, true)
            case .paused: return ("Wstrzymane", .orange, false)
            case .failed: return ("Brak dostępu", .orange, false)
            }
        }()
        return HStack(spacing: 6) {
            StatusDot(color: color, pulsing: pulsing).id(label)
            Text(label)
                .font(.caption.weight(.medium))
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .animation(snappy, value: label)
    }

    // MARK: Sources (Loom-style rows)

    private var sources: some View {
        VStack(spacing: 6) {
            SourceRow(icon: "speaker.wave.2.fill", title: "Dźwięk komputera", isOn: state.includeSystemAudio) {
                if state.includeSystemAudio { TrackMeter(levels: state.levels, track: .system) }
                OnOffPill(isOn: $state.includeSystemAudio)
            }
            SourceRow(icon: state.includeMic ? "mic.fill" : "mic.slash.fill", title: "Mikrofon", isOn: state.includeMic) {
                MicMenu(state: state)
                if state.includeMic { TrackMeter(levels: state.levels, track: .mic) }
                OnOffPill(isOn: $state.includeMic)
            }
            if state.includeMic, state.activeMic?.isBluetooth == true {
                Label("Mikrofon w słuchawkach Bluetooth pogarsza jakość muzyki.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .disabled(state.isRecording)
    }

    // MARK: Action

    @ViewBuilder
    private var actionArea: some View {
        if state.isRecording {
            // Whereby-style recording card
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    PulsingDot()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nagrywanie").font(.subheadline.weight(.semibold))
                        Text(state.markerCount == 0 ? "od \(state.bufferLabel) wstecz" : "od \(state.bufferLabel) wstecz · znaczniki: \(state.markerCount)")
                            .font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text(formatDuration(state.elapsed))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(state.elapsed))
                }
                HStack(spacing: 8) {
                    Button(action: state.addMarker) {
                        Label("Znacznik", systemImage: "bookmark.fill")
                            .symbolEffect(.bounce, value: state.markerCount)
                    }
                    .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.1), foreground: .primary))
                    .fixedSize()
                    Button(action: state.toggleClip) {
                        Label("Zatrzymaj i zapisz", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BigButtonStyle(fill: accent))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.3)))
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            VStack(spacing: 8) {
                Button(action: state.toggleClip) {
                    Label("Nagrywaj od \(state.bufferLabel) wstecz", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: accent))
                Button(action: state.saveInstantClip) {
                    Label("Zapisz ostatnie \(state.bufferLabel)", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.08), foreground: .primary))
                HStack(spacing: 6) {
                    ShortcutHint(combo: state.toggleCombo, text: "nagraj")
                    ShortcutHint(combo: state.instantCombo, text: "zapisz")
                    ShortcutHint(combo: state.markerCombo, text: "znacznik")
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity)
            }
            .disabled(state.status != .buffering)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func pausedCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reason).font(.subheadline.weight(.semibold))
                    Text("Aplikacja nic teraz nie nagrywa.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.userPaused {
                    Button("Wznów", action: state.resume)
                        .buttonStyle(BigButtonStyle(fill: onColor))
                        .fixedSize()
                }
            }
            if state.isPowerPaused {
                Button(action: state.resumeDespitePower) {
                    Label("Nagrywaj mimo to", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.08), foreground: .primary))
                .help("Do następnej zmiany zasilania")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
    }

    private func permissionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.permissionGranted {
                Label("Dostęp nadany", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onColor)
                Text("Uruchom aplikację ponownie, żeby zaczęła nagrywać.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: state.relaunch) {
                    Label("Uruchom ponownie", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: onColor))
            } else {
                Label("Potrzebny dostęp", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Otwórz Ustawienia", action: state.openPrivacySettings)
                        .buttonStyle(BigButtonStyle(fill: accent))
                    Button("Uruchom ponownie", action: state.relaunch)
                        .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.08), foreground: .primary))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
    }

    // MARK: Recent clips

    private var recentClips: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Ostatnie klipy").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if state.isFinalizing {
                    ProgressView().controlSize(.mini).transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Button("Pokaż folder", action: state.openClipsFolder)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            ForEach(state.recentClips.prefix(3), id: \.self) { url in
                ClipRow(url: url, state: state, info: state.clipInfo)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(snappy, value: state.isFinalizing)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            PauseButton(state: state)
            Spacer()
            AccountButton(state: state, cloud: state.cloud)
            Button {
                state.openSettings()
            } label: {
                Label("Ustawienia", systemImage: "gearshape").fixedSize()
            }
            Button("Zakończ") { NSApp.terminate(nil) }.fixedSize()
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}

private extension AnyTransition {
    static var cardSwap: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity)
    }
}

// MARK: - Components

private struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        if let release = updater.available {
            Button { NSWorkspace.shared.open(release.url) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(onColor)
                        .symbolEffect(.bounce, value: release.version)
                    Text("Dostępna wersja \(release.version)").font(.caption.weight(.semibold))
                    Spacer()
                    Text("Pobierz").font(.caption).foregroundStyle(onColor)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(onColor.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct MicMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            Picker("", selection: $state.micSelection) {
                Text("Automatycznie").tag(Microphones.auto)
                Divider()
                ForEach(state.microphones) { mic in
                    Text(mic.isBluetooth ? "\(mic.name) – Bluetooth" : mic.name).tag(mic.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(state.activeMic?.name ?? "Brak")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 96)
        .disabled(!state.includeMic)
    }
}

/// "Wstrzymaj" with a choice of how long; "Wznów" while paused.
struct PauseButton: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.userPaused {
            Button(action: state.resume) {
                Label("Wznów", systemImage: "play.fill")
            }
        } else {
            PopupMenuButton(items: {
                [PopupMenuItem(title: "Na 15 minut") { state.pause(for: 15 * 60) },
                 PopupMenuItem(title: "Na godzinę") { state.pause(for: 3600) },
                 PopupMenuItem(title: "Do wznowienia") { state.pause(for: nil) }]
            }) {
                Label("Wstrzymaj", systemImage: "pause.fill")
            }
            .fixedSize()
            .disabled(state.isRecording)
            .help("Wstrzymaj nagrywanie w tle")
        }
    }
}

/// Account entry in the popover footer: "Zaloguj się" or the account menu.
private struct AccountButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var cloud: CloudService

    var body: some View {
        if let account = cloud.account {
            PopupMenuButton(items: {
                [.header(account.email),
                 PopupMenuItem(title: "Moje klipy") { cloud.openDashboard() },
                 PopupMenuItem(title: "Ustawienia konta…") { state.openSettings(.account) },
                 .separator,
                 PopupMenuItem(title: "Wyloguj") { cloud.signOut() }]
            }) {
                Label(account.name.isEmpty ? account.username : account.name, systemImage: "person.crop.circle.fill")
                    .lineLimit(1)
            }
            .frame(maxWidth: 110)
            .help("Twoje konto")
        } else {
            Button {
                cloud.startLogin()
            } label: {
                Label("Zaloguj", systemImage: "person.crop.circle.badge.plus")
                    .lineLimit(1)
                    .fixedSize()
            }
            .disabled(cloud.pendingLogin != nil)
            .help("Zaloguj się, aby udostępniać klipy linkiem")
        }
    }
}

/// Actions available for a saved clip (shared by the popover rows and the preview).
struct ClipActionsMenu: View {
    let url: URL
    @ObservedObject var state: AppState

    var body: some View {
        if state.shares[url] != nil {
            Button("Anuluj wysyłanie") { state.cancelShare(url) }
        } else if state.cloud.link(for: url) != nil {
            Button("Kopiuj link") { state.shareLink(url) }
            Button("Otwórz link") { state.openLink(url) }
        } else {
            Button("Udostępnij link") { state.shareLink(url) }
        }
        Divider()
        Button("Otwórz") { state.open(url) }
        Button("Pokaż w Finderze") { state.reveal(url) }
        Button("Kopiuj plik") { state.copyToPasteboard(url) }
        Divider()
        Button("Przytnij…") { state.trim(url) }
        Divider()
        Button("Przenieś do Kosza", role: .destructive) { state.delete(url) }
    }
}

private struct SourceRow<Trailing: View>: View {
    let icon: String
    let title: String
    let isOn: Bool
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(isOn ? .primary : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(.callout).lineLimit(1)
                .foregroundStyle(isOn ? .primary : .secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .animation(snappy, value: isOn)
    }
}

/// On/Off pill with a sliding knob.
private struct OnOffPill: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(snappy) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? onColor : accent)
                Text(isOn ? "On" : "Off")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: isOn ? .leading : .trailing)
                    .padding(.horizontal, 6)
                Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            .frame(width: 44, height: 18)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Będzie słychać w klipie" : "Nie będzie słychać w klipie")
    }
}

private struct ShortcutHint: View {
    let combo: KeyCombo?
    let text: String

    var body: some View {
        if let combo {
            HStack(spacing: 3) {
                KeyCaps(keys: combo.keys)
                Text(text).font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
        }
    }
}

private struct ClipRow: View {
    let url: URL
    @ObservedObject var state: AppState
    @ObservedObject var info: ClipInfoStore
    @StateObject private var hover = Flag()

    var body: some View {
        let details = info.info(for: url)
        HStack(spacing: 10) {
            thumbnail(details?.thumbnail)
            VStack(alignment: .leading, spacing: 1) {
                Text(ClipInfoStore.label(for: details?.created ?? created))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(details.map { "\(formatDuration($0.duration)) · \(ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file))" } ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let progress = state.shares[url] {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .controlSize(.small)
                    .tint(accent)
                    .transition(.scale.combined(with: .opacity))
            } else if hover.value {
                HStack(spacing: 6) {
                    Button { state.shareLink(url) } label: {
                        Image(systemName: state.cloud.link(for: url) == nil ? "link" : "doc.on.doc")
                    }
                    .help(state.cloud.link(for: url) == nil ? "Udostępnij link" : "Kopiuj link")
                    Button { state.trim(url) } label: { Image(systemName: "scissors") }
                        .help("Przytnij")
                    Menu {
                        ClipActionsMenu(url: url, state: state)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover.value ? 0.07 : 0)))
        // Keyed on the file's version, so a trimmed clip gets a fresh thumbnail.
        .task(id: modified) { info.load(url) }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover.value = h } }
        .onTapGesture(count: 2) { state.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { ClipActionsMenu(url: url, state: state) }
        .animation(snappy, value: (state.shares[url]) != nil)
        .help("Kliknij dwa razy, aby otworzyć. Prawy klik: więcej opcji.")
    }

    private var modified: Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private var created: Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private func thumbnail(_ image: NSImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "film").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 27)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
        .overlay(alignment: .bottomTrailing) {
            if state.cloud.link(for: url) != nil {
                Image(systemName: "link")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(onColor))
                    .offset(x: 4, y: 4)
                    .help("Udostępniony linkiem")
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
    }
}
