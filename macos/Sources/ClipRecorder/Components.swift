import SwiftUI

let accent = Color(red: 0.96, green: 0.36, blue: 0.29)   // coral red (record)
let onColor = Color(red: 0.24, green: 0.69, blue: 0.62)  // teal ("On", healthy levels)
let warnColor = Color(red: 0.98, green: 0.75, blue: 0.25)

let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)

/// Live audio level – ascending bars that light up (Mistral / VEED style).
struct LevelMeter: View {
    var level: Float
    var bars = 5
    var height: CGFloat = 14
    var dimmed: Color = .primary.opacity(0.15)

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                let lit = level > Float(i) / Float(bars) + 0.02
                Capsule()
                    .fill(lit ? color(i) : dimmed)
                    .frame(width: 3, height: height * (0.35 + 0.65 * CGFloat(i + 1) / CGFloat(bars)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityLabel("Audio level")
    }

    private func color(_ i: Int) -> Color {
        switch Double(i) / Double(bars) {
        case ..<0.55: return onColor
        case ..<0.8: return warnColor
        default: return accent
        }
    }
}

/// Meter bound to the shared `AudioLevels` object (keeps 15 Hz updates local to this view).
struct TrackMeter: View {
    enum Track { case system, mic }
    @ObservedObject var levels: AudioLevels
    let track: Track
    var height: CGFloat = 14
    var dimmed: Color = .primary.opacity(0.15)

    var body: some View {
        LevelMeter(level: track == .system ? levels.system : levels.mic, height: height, dimmed: dimmed)
    }
}

/// Capsule button with hover lift and spring press.
struct BigButtonStyle: ButtonStyle {
    let fill: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        BigButtonBody(configuration: configuration, fill: fill, foreground: foreground)
    }

    private struct BigButtonBody: View {
        let configuration: Configuration
        let fill: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled
        @StateObject private var hover = Flag()

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(fill)
                        .brightness(hover.value && isEnabled ? 0.06 : 0)
                        .shadow(color: fill.opacity(hover.value && isEnabled ? 0.35 : 0), radius: 8, y: 3)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(snappy, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover.value)
                .onHover { hover.value = $0 }
        }
    }
}

/// Separate key caps for each key of a shortcut (Amie / Discord style).
struct KeyCaps: View {
    let keys: [String]
    var dark = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background(RoundedRectangle(cornerRadius: 5).fill(dark ? Color.white.opacity(0.12) : Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(dark ? Color.white.opacity(0.15) : Color.primary.opacity(0.14)))
                    .shadow(color: .black.opacity(dark ? 0 : 0.06), radius: 0, y: 1)
            }
        }
    }
}

/// Status dot that "breathes" (buffering) or pulses (recording).
struct StatusDot: View {
    let color: Color
    var pulsing = true
    @StateObject private var phase = Flag()

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 7, height: 7)
                .scaleEffect(pulsing && phase.value ? 2.2 : 1)
                .opacity(pulsing && phase.value ? 0 : 1)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { phase.value = true }
        }
    }
}

struct PulsingDot: View {
    var size: CGFloat = 10
    @StateObject private var pulse = Flag()

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: size, height: size)
            .opacity(pulse.value ? 1 : 0.35)
            .shadow(color: accent.opacity(pulse.value ? 0.8 : 0), radius: 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse.value = true }
            }
    }
}

/// Inline toast (v0 / Base44 style): icon + text in a soft capsule.
struct Toast: View {
    enum Kind { case success, error, info }
    let text: String

    private var kind: Kind {
        // Messages are plain localized text – recognise them by wording (English and Polish).
        let t = text.lowercased()
        let errors = ["failed", "couldn’t", "interrupted", "no space", "no connection", "not enough",
                      "nie powiódł", "nie powiodło", "nie udało", "przerwane", "brak", "za mało"]
        let successes = ["saved:", "trimmed", "moved to trash", "link copied", "signed in as",
                         "zapisano", "przycięto", "przeniesiono", "link skopiowany", "zalogowano"]
        if errors.contains(where: t.contains) { return .error }
        if successes.contains(where: t.hasPrefix) { return .success }
        return .info
    }

    var body: some View {
        let (icon, color): (String, Color) = {
            switch kind {
            case .success: return ("checkmark.circle.fill", onColor)
            case .error: return ("exclamationmark.triangle.fill", accent)
            case .info: return ("info.circle.fill", .secondary)
            }
        }()
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
                .symbolEffect(.bounce, value: text)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.2)))
    }
}

/// Tiny observable flag (used instead of `@State`, whose macro isn't shipped
/// with the Command Line Tools toolchain).
final class Flag: ObservableObject {
    @Published var value = false
}

/// Editable text kept outside the bound model until committed.
final class TextDraft: ObservableObject {
    @Published var text = ""
}

/// Entry of a `PopupMenuButton` menu.
struct PopupMenuItem {
    var title: String
    var enabled = true
    var action: (() -> Void)?

    static let separator = PopupMenuItem(title: "")
    static func header(_ title: String) -> PopupMenuItem { PopupMenuItem(title: title, enabled: false) }
}

/// A plain button that opens a native menu under the mouse. SwiftUI's `Menu`
/// always draws a system pop-up button, which doesn't match borderless footers.
struct PopupMenuButton<Label: View>: View {
    let items: () -> [PopupMenuItem]
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items() {
                if item.title.isEmpty { menu.addItem(.separator()); continue }
                let entry = ClosureMenuItem(title: item.title) { item.action?() }
                entry.isEnabled = item.enabled && item.action != nil
                menu.addItem(entry)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            label
        }
    }
}
