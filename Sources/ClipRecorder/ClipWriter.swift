import AVFoundation
import CoreMedia

/// Writes one clip: passthrough HEVC video + system audio and microphone as
/// two separate AAC tracks in a QuickTime (.mov) file.
final class ClipWriter {
    private let url: URL
    private let writer: AVAssetWriter
    private var inputs: [CaptureEngine.Track: AVAssetWriterInput] = [:]
    private let queue = DispatchQueue(label: "ClipRecorder.writer", qos: .userInitiated)
    private var finished = false
    private var reportedFailure = false
    /// Called once (on the writer queue) when writing breaks mid-clip, e.g. disk full.
    var onFailure: ((Error) -> Void)?

    init(url: URL, videoFormat: CMFormatDescription, systemFormat: CMFormatDescription?,
         micFormat: CMFormatDescription?, startTime: CMTime) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Fragments every few seconds: if the app quits or crashes mid-recording,
        // everything up to the last fragment still plays.
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        video.expectsMediaDataInRealTime = true
        try add(video, for: .video, name: "Ekran")

        if let systemFormat {
            try add(Self.audioInput(for: systemFormat, bitrate: 192_000), for: .system, name: "Dźwięk systemu")
        }
        if let micFormat {
            try add(Self.audioInput(for: micFormat, bitrate: 128_000), for: .mic, name: "Mikrofon")
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "ClipRecorder", code: 2)
        }
        writer.startSession(atSourceTime: startTime)
    }

    private func add(_ input: AVAssetWriterInput, for track: CaptureEngine.Track, name: String) throws {
        let title = AVMutableMetadataItem()
        title.identifier = .quickTimeUserDataTrackName
        title.value = name as NSString
        input.metadata = [title]
        guard writer.canAdd(input) else {
            throw NSError(domain: "ClipRecorder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Nie można dodać ścieżki „\(name)”."])
        }
        writer.add(input)
        inputs[track] = input
    }

    private static func audioInput(for format: CMFormatDescription, bitrate: Int) -> AVAssetWriterInput {
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        let channels = min(max(Int(asbd?.mChannelsPerFrame ?? 2), 1), 2)
        // Always 48 kHz: AAC can't encode the 8/16 kHz some headset mics deliver,
        // and the writer resamples on its own.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate * channels / 2,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        return input
    }

    func append(_ sample: CMSampleBuffer, to track: CaptureEngine.Track) {
        nonisolated(unsafe) let sample = sample
        append({ sample }, to: track)
    }

    /// `load` runs on the writer queue, so disk-buffered samples are read lazily.
    func append(_ load: @escaping () -> CMSampleBuffer?, to track: CaptureEngine.Track) {
        queue.async {
            guard !self.finished, let input = self.inputs[track] else { return }
            guard self.writer.status == .writing else { self.reportFailure(); return }
            guard let sample = load() else { return }
            // A dropped video frame breaks the picture until the next keyframe, so wait
            // generously (the writer is only briefly busy, e.g. while writing a fragment).
            var waits = 0
            while !input.isReadyForMoreMediaData && waits < 2000 && self.writer.status == .writing {
                usleep(5_000)
                waits += 1
            }
            guard input.isReadyForMoreMediaData else {
                NSLog("ClipRecorder: dropped sample on \(track) – writer busy")
                return
            }
            if !input.append(sample) {
                NSLog("ClipRecorder: append failed on \(track): \(String(describing: self.writer.error))")
                self.reportFailure()
            }
        }
    }

    private func reportFailure() {
        guard !reportedFailure, writer.status == .failed else { return }
        reportedFailure = true
        onFailure?(writer.error ?? NSError(domain: "ClipRecorder", code: 6))
    }

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            // Stop can be requested twice (hotkey + pause, stream error…); finishing
            // an AVAssetWriter twice throws an Objective-C exception.
            guard !self.finished else { return }
            self.finished = true
            guard self.writer.status == .writing else {
                completion(.failure(self.writer.error ?? NSError(domain: "ClipRecorder", code: 4)))
                return
            }
            self.inputs.values.forEach { $0.markAsFinished() }
            self.writer.finishWriting {
                if self.writer.status == .completed {
                    completion(.success(self.url))
                } else {
                    completion(.failure(self.writer.error ?? NSError(domain: "ClipRecorder", code: 5)))
                }
            }
        }
    }
}
