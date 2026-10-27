import CoreGraphics
import Foundation

/// Everything the capture engine needs to know. Changing a "restart" field
/// restarts the stream (and drops the buffer); other fields apply live.
struct CaptureSettings: Equatable {
    enum Source: Equatable, Codable, Hashable {
        case mainDisplay
        case display(CGDirectDisplayID)
        case app(bundleID: String, name: String)
    }

    enum Quality: String, CaseIterable, Codable, Identifiable {
        case low, medium, high
        var id: String { rawValue }
        var label: String {
            switch self {
            case .low: return "Niska"
            case .medium: return "Średnia"
            case .high: return "Wysoka"
            }
        }
        /// Bits per pixel per frame for HEVC.
        var bitsPerPixel: Double {
            switch self {
            case .low: return 0.025
            case .medium: return 0.045
            case .high: return 0.08
            }
        }
    }

    var source: Source = .mainDisplay
    var maxHeight: Int = 0          // 0 = native resolution
    var fps: Int = 60
    var quality: Quality = .medium
    var bufferSeconds: Int = 60
    var includeSystemAudio = true
    var includeMic = true
    var micDeviceID: String?
    var excludedBundleIDs: [String] = []

    /// Buffers longer than this are kept on disk instead of in RAM.
    static let maxRAMBufferSeconds = 120
    var buffersOnDisk: Bool { bufferSeconds > Self.maxRAMBufferSeconds }

    func needsRestart(comparedTo other: CaptureSettings) -> Bool {
        source != other.source || maxHeight != other.maxHeight || fps != other.fps
            || quality != other.quality || buffersOnDisk != other.buffersOnDisk
    }
}

/// How the extra "Miks" track is built after a clip is saved.
struct MixSettings: Equatable {
    var systemVolume: Float = 1.0
    var micVolume: Float = 1.0
    var limiter = true
}

/// A global keyboard shortcut (Carbon key code + Carbon modifier mask).
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
}

/// Chapter written into the finished clip (time in seconds from the clip start).
struct Chapter: Equatable {
    var time: Double
    var title: String
}

/// Small helper for persisting Codable values in UserDefaults.
enum Defaults {
    static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
