import SwiftUI

/// Floating recording bar at the top of the screen (Canva's recording pill:
/// timer · live levels · actions). Clickable, but excluded from the capture.
struct RecordingHUD: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                PulsingDot(size: 9)
                Text(formatDuration(state.elapsed))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(state.elapsed))
            }
            .padding(.leading, 4)

            separator

            HStack(spacing: 8) {
                if state.includeSystemAudio {
                    meter(icon: "speaker.wave.2.fill", track: .system)
                }
                if state.includeMic {
                    meter(icon: "mic.fill", track: .mic)
                }
            }

            separator

            Button(action: state.addMarker) {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .symbolEffect(.bounce, value: state.markerCount)
                    if state.markerCount > 0 {
                        Text("\(state.markerCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                }
                .frame(minWidth: 28, minHeight: 26)
                .padding(.horizontal, 4)
                .background(Capsule().fill(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Dodaj znacznik" + (state.markerCombo.map { " (\($0.label))" } ?? ""))

            Button(action: state.toggleClip) {
                Label("Zapisz", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
            .help("Zatrzymaj i zapisz" + (state.toggleCombo.map { " (\($0.label))" } ?? ""))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.09).opacity(0.94)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(14)  // room for the shadow
        .fixedSize()
        .animation(snappy, value: state.markerCount)
        .environment(\.colorScheme, .dark)
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 16)
    }

    private func meter(icon: String, track: TrackMeter.Track) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            TrackMeter(levels: state.levels, track: track, height: 12, dimmed: .white.opacity(0.18))
        }
    }
}
