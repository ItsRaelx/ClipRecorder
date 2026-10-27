import SwiftUI

/// Menu bar popover. Layout follows Loom's recorder popover (source rows with
/// On/Off pills + one big action button), Whereby's recording card and
/// v0/Base44-style inline toasts. Live level meters follow Mistral/VEED.
struct PopoverView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
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
            case .buffering: return ("Bufor \(state.bufferLabel)", onColor, true)
            case .recording: return ("Nagrywanie", accent, true)
            case .paused: return ("Wstrzymany", .orange, false)
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
            SourceRow(icon: "speaker.wave.2.fill", title: "Dźwięk systemu", isOn: state.includeSystemAudio) {
                if state.includeSystemAudio { TrackMeter(levels: state.levels, track: .system) }
                OnOffPill(isOn: $state.includeSystemAudio)
            }
            SourceRow(icon: state.includeMic ? "mic.fill" : "mic.slash.fill", title: "Mikrofon", isOn: state.includeMic) {
                MicMenu(state: state)
                if state.includeMic { TrackMeter(levels: state.levels, track: .mic) }
                OnOffPill(isOn: $state.includeMic)
            }
            if state.includeMic, state.activeMic?.isBluetooth == true {
                Label("Mikrofon Bluetooth przełącza słuchawki w tryb rozmowy – muzyka zagra w gorszej jakości.",
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
                        Text(state.markerCount == 0 ? "z \(state.bufferLabel) bufora" : "z \(state.bufferLabel) bufora · znaczniki: \(state.markerCount)")
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
                    Label("Klipuj ostatnie \(state.bufferLabel) i nagrywaj", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: accent))
                Button(action: state.saveInstantClip) {
                    Label("Zapisz tylko ostatnie \(state.bufferLabel)", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.08), foreground: .primary))
                HStack(spacing: 12) {
                    ShortcutHint(combo: state.toggleCombo, text: "klip")
                    ShortcutHint(combo: state.instantCombo, text: "zapis")
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
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(reason).font(.subheadline.weight(.semibold))
                Text("Ekran i dźwięk nie są teraz buforowane.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.userPaused {
                Button("Wznów") { state.userPaused = false }
                    .buttonStyle(BigButtonStyle(fill: onColor))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.1)))
    }

    private func permissionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Potrzebny dostęp", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Otwórz Ustawienia", action: state.openPrivacySettings)
                    .buttonStyle(BigButtonStyle(fill: accent))
                Button("Spróbuj ponownie", action: state.start)
                    .buttonStyle(BigButtonStyle(fill: .primary.opacity(0.08), foreground: .primary))
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
            ForEach(state.recentClips.prefix(4), id: \.self) { url in
                ClipRow(url: url, state: state)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(snappy, value: state.isFinalizing)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                state.togglePause()
            } label: {
                Label(state.userPaused ? "Wznów bufor" : "Wstrzymaj",
                      systemImage: state.userPaused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(state.isRecording)
            Spacer()
            Button {
                state.openSettings()
            } label: {
                Label("Ustawienia", systemImage: "gearshape")
            }
            Button("Zakończ") { NSApp.terminate(nil) }
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

struct MicMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            Picker("", selection: $state.micSelection) {
                Text("Automatycznie (omija mikrofony Bluetooth)").tag(Microphones.auto)
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

/// Actions available for a saved clip (shared by the popover rows and the preview).
struct ClipActionsMenu: View {
    let url: URL
    @ObservedObject var state: AppState

    var body: some View {
        Button("Otwórz") { state.open(url) }
        Button("Pokaż w Finderze") { state.reveal(url) }
        Button("Kopiuj plik") { state.copyToPasteboard(url) }
        Divider()
        Button("Przytnij…") { state.trim(url) }
        Menu("Eksportuj MP4 (tylko miks)") {
            ForEach(ShareExporter.Target.allCases) { target in
                Button(target.label) { state.export(url, target: target) }
            }
        }
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
        .help(isOn ? "Ścieżka będzie zapisana w klipie" : "Ścieżka zostanie pominięta")
    }
}

private struct ShortcutHint: View {
    let combo: KeyCombo?
    let text: String

    var body: some View {
        if let combo {
            HStack(spacing: 5) {
                KeyCaps(keys: combo.keys)
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClipRow: View {
    let url: URL
    @ObservedObject var state: AppState
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .foregroundStyle(hover.value ? accent : .secondary)
            Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Klip ", with: ""))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let progress = state.exports[url] {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .controlSize(.small)
                    .tint(accent)
                    .transition(.scale.combined(with: .opacity))
            } else if hover.value {
                HStack(spacing: 6) {
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
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover.value ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover.value = h } }
        .onTapGesture(count: 2) { state.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu { ClipActionsMenu(url: url, state: state) }
        .animation(snappy, value: state.exports[url] != nil)
        .help("Kliknij dwukrotnie, aby otworzyć · przeciągnij, aby wrzucić gdzie indziej · prawy klik: więcej")
    }
}
