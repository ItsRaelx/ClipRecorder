import AVFoundation

/// Exports a clip as an H.264 MP4 with a single audio track (the mix), optionally
/// squeezed under a file-size limit (Discord etc.).
enum ShareExporter {
    enum Target: String, CaseIterable, Identifiable {
        case discord10, discord50, full
        var id: String { rawValue }
        var label: String {
            switch self {
            case .discord10: return "Discord (do 10 MB)"
            case .discord50: return "Discord Nitro Basic (do 50 MB)"
            case .full: return "Pełna jakość"
            }
        }
        var maxBytes: Double? {
            switch self {
            case .discord10: return 10 * 1_000_000
            case .discord50: return 50 * 1_000_000
            case .full: return nil
            }
        }
        var audioBitrate: Double {
            switch self {
            case .discord10: return 96_000
            case .discord50: return 128_000
            case .full: return 192_000
            }
        }
        var fileSuffix: String {
            switch self {
            case .discord10: return " (10 MB)"
            case .discord50: return " (50 MB)"
            case .full: return ""
            }
        }
    }

    static func export(_ url: URL, target: Target, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + target.fileSuffix + ".mp4")
        var safety = 0.92
        for _ in 0..<2 {
            try await encode(url, to: destination, target: target, sizeSafety: safety, progress: progress)
            guard let limit = target.maxBytes,
                  let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Double(size) > limit else { return destination }
            safety *= limit / Double(size) * 0.95  // overshot – try once more with a lower bitrate
        }
        return destination
    }

    private static func encode(_ url: URL, to destination: URL, target: Target, sizeSafety: Double,
                               progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0, let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audio: AVAssetTrack?
        for track in audioTracks where await ClipFinalizer.trackName(track) == ClipFinalizer.mixName { audio = track }
        if audio == nil { audio = audioTracks.first }

        let natural = try await video.load(.naturalSize)
        let sourceFPS = Double(try await video.load(.nominalFrameRate))

        // Budget → bitrate → resolution / frame rate.
        let audioBitrate = audio == nil ? 0 : target.audioBitrate
        var videoBitrate: Double
        var maxHeight: Double
        var fps = sourceFPS > 1 ? min(sourceFPS, 60) : 60
        if let limit = target.maxBytes {
            videoBitrate = max((limit * 8 * sizeSafety - audioBitrate * duration) / duration, 150_000)
            switch videoBitrate {
            case 5_000_000...: maxHeight = 1080
            case 2_500_000...: maxHeight = 720
            case 1_000_000...: maxHeight = 540
            default: maxHeight = 360
            }
            if videoBitrate < 3_000_000 { fps = min(fps, 30) }
        } else {
            maxHeight = 2160
            videoBitrate = 0
        }
        let scale = min(1, maxHeight / natural.height)
        let width = (Int(natural.width * scale) / 2) * 2
        let height = (Int(natural.height * scale) / 2) * 2
        if target.maxBytes == nil {
            videoBitrate = min(max(Double(width * height) * fps * 0.05, 4_000_000), 25_000_000)
        }

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(videoBitrate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: Int(fps),
                AVVideoAllowFrameReorderingKey: true,
            ],
        ])
        writer.add(videoIn)

        var pumps: [(next: () -> CMSampleBuffer?, input: AVAssetWriterInput)] = []
        let minFrameGap = 1 / fps - 0.002
        var lastKept = -Double.infinity
        pumps.append(({
            // Drop frames to reach the target frame rate.
            while let sample = videoOut.copyNextSampleBuffer() {
                let t = sample.presentationTimeStamp.seconds
                if t - lastKept < minFrameGap { continue }
                lastKept = t
                progress(min(t / duration, 1))
                return sample
            }
            return nil
        }, videoIn))

        if let audio {
            let audioOut = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(audioOut)
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: Int(audioBitrate),
            ])
            writer.add(audioIn)
            pumps.append((audioOut.copyNextSampleBuffer, audioIn))
        }

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        await withTaskGroup(of: Void.self) { tasks in
            for pump in pumps {
                nonisolated(unsafe) let pump = pump
                tasks.addTask { await ClipFinalizer.run(pump.next, into: pump.input) }
            }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        progress(1)
    }
}
