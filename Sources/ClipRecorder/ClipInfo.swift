import AppKit
import AVFoundation

/// Thumbnail, length and size of saved clips for the "Ostatnie klipy" list.
/// Loaded lazily in the background and cached per file version (path + modification
/// date), so a trimmed clip gets a fresh entry.
@MainActor
final class ClipInfoStore: ObservableObject {
    struct Info {
        var thumbnail: NSImage?
        var duration: Double
        var size: Int
        var created: Date
    }

    @Published private(set) var infos: [String: Info] = [:]
    private var loading = Set<String>()

    func info(for url: URL) -> Info? { infos[key(url)] }

    /// For UI snapshots: pretend a clip was already read.
    func preload(_ url: URL, _ info: Info) { infos[key(url)] = info }

    func load(_ url: URL) {
        let key = key(url)
        guard infos[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        Task {
            let info = await Self.read(url)
            loading.remove(key)
            if let info { infos[key] = info }
        }
    }

    private func key(_ url: URL) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return "\(url.path)|\(modified.timeIntervalSince1970)"
    }

    nonisolated private static func read(_ url: URL) async -> Info? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        guard let values else { return nil }
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        let time = CMTime(seconds: max(0, duration - 1), preferredTimescale: 600)
        let image = try? await generator.image(at: time).image
        return Info(thumbnail: image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) },
                    duration: duration.isFinite ? duration : 0,
                    size: values.fileSize ?? 0,
                    created: values.creationDate ?? Date())
    }

    /// "Dziś, 21:06" / "Wczoraj, 20:45" / "27 paź, 19:12".
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Dziś, \(time)" }
        if calendar.isDateInYesterday(date) { return "Wczoraj, \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated)) + ", " + time
    }
}
