import AVFoundation

/// Converts a clip for clip.secc.me: H.264 MP4 up to 1080p with a single audio
/// track (the mix), so it plays in every browser.
enum ShareExporter {
    static func export(_ url: URL, to directory: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".mp4")
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
        // The nominal rate is an average – static stretches (re-encoded only twice a
        // second) pull it way down. The shortest frame gap is the real capture rate.
        let minFrame = try await video.load(.minFrameDuration).seconds
        let sourceFPS = minFrame > 0 && minFrame.isFinite ? (1 / minFrame).rounded() : 60
        let fps = min(max(sourceFPS, 15), 60)

        let scale = min(1, 1080 / natural.height)
        let width = (Int(natural.width * scale) / 2) * 2
        let height = (Int(natural.height * scale) / 2) * 2
        let videoBitrate = min(max(Double(width * height) * fps * 0.04, 2_500_000), 8_000_000)

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
                AVEncoderBitRateKey: 160_000,
            ])
            writer.add(audioIn)
            pumps.append((audioOut.copyNextSampleBuffer, audioIn))
        }

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        // Cancelling the task stops reading, so the pumps drain and finish early.
        nonisolated(unsafe) let cancellableReader = reader
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { tasks in
                for pump in pumps {
                    nonisolated(unsafe) let pump = pump
                    tasks.addTask { await ClipFinalizer.run(pump.next, into: pump.input, writer: writer) }
                }
            }
        } onCancel: {
            cancellableReader.cancelReading()
        }
        if Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        if reader.status == .failed || writer.status != .writing {
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: destination)
            throw reader.error ?? writer.error ?? CocoaError(.fileReadUnknown)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        progress(1)
        return destination
    }
}
