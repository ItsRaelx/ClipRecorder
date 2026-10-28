import Foundation

/// Clip files on disk: naming, listing and automatic cleanup.
enum ClipLibrary {
    static let defaultDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clips", isDirectory: true)

    static func newClipURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'o' HH.mm.ss"
        let name = "Klip \(formatter.string(from: Date()))"
        // Two clips within the same second (double-tapped hotkey) must not collide.
        var url = directory.appendingPathComponent("\(name).mov")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) (\(n)).mov")
            n += 1
        }
        return url
    }

    struct Entry {
        let url: URL
        let created: Date
        let size: Int
    }

    /// Clips made by this app, newest first.
    static func clips(in directory: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("Klip ") && ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Entry(url: url, created: values?.creationDate ?? .distantPast, size: values?.fileSize ?? 0)
            }
            .sorted { $0.created > $1.created }
    }

    /// Moves clips to the Trash when older than `maxAgeDays` or when the folder
    /// exceeds `maxGB` (oldest first). 0 disables a rule. Returns the number removed.
    @discardableResult
    static func cleanup(in directory: URL, maxAgeDays: Int, maxGB: Int, keeping protected: Set<URL> = []) -> Int {
        var entries = clips(in: directory).filter { !protected.contains($0.url) }
        var removed = 0
        if maxAgeDays > 0 {
            let limit = Date().addingTimeInterval(-Double(maxAgeDays) * 86_400)
            for entry in entries where entry.created < limit {
                if (try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)) != nil { removed += 1 }
            }
            entries.removeAll { $0.created < limit }
        }
        if maxGB > 0 {
            var total = entries.reduce(0) { $0 + $1.size }
            let limit = maxGB * 1_000_000_000
            for entry in entries.reversed() where total > limit {
                if (try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)) != nil {
                    total -= entry.size
                    removed += 1
                }
            }
        }
        return removed
    }
}
