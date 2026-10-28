import AVFoundation

/// Rewrites a clip in place (video and original audio are copied without re-encoding):
/// - adds a "Mix" track (system + mic, with per-track volume and a limiter) as the
///   first, default audio track, so single-track players hear everything,
/// - writes chapters (buffer start, recording start, markers),
/// - optionally trims to a time range.
enum ClipFinalizer {
    /// Name of the mix track written into new clips (in the app's language).
    static let mixName = String(localized: "Mix (system + microphone)")
    /// Every name the mix track may have – clips made in another language keep theirs.
    static let mixNames: Set<String> = [mixName, "Miks (system + mikrofon)", "Mix (system + microphone)"]

    static func isMix(_ name: String?) -> Bool { name.map(mixNames.contains) ?? false }

    struct Options {
        /// Build a mix track if the clip has ≥ 2 audio tracks and no mix yet.
        var mix: MixSettings?
        /// `nil` keeps the clip's existing chapters.
        var chapters: [Chapter]?
        var timeRange: CMTimeRange?
    }

    static func process(_ url: URL, options: Options) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        var audioTracks: [(track: AVAssetTrack, name: String?)] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            audioTracks.append((track, await trackName(track)))
        }
        let existingMix = audioTracks.first { isMix($0.name) }
        let sources = audioTracks.filter { !isMix($0.name) }

        let range = options.timeRange ?? CMTimeRange(start: .zero, duration: duration)
        let chapters: [Chapter]
        if let given = options.chapters {
            chapters = given
        } else {
            chapters = await existingChapters(of: asset)
        }

        let reader = try AVAssetReader(asset: asset)
        if options.timeRange != nil { reader.timeRange = range }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mov)
        var pumps: [(next: () -> CMSampleBuffer?, input: AVAssetWriterInput)] = []

        func passthrough(_ track: AVAssetTrack, name: String?) async throws -> AVAssetWriterInput {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            let hint = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: hint)
            if let name { input.metadata = [trackNameItem(name)] }
            writer.add(input)
            pumps.append((output.copyNextSampleBuffer, input))
            return input
        }

        var videoInput: AVAssetWriterInput?
        for track in videoTracks {
            // A re-run (trim) keeps the name the clip was made with.
            let name = await trackName(track) ?? String(localized: "Screen")
            videoInput = try await passthrough(track, name: name)
        }

        var audioInputs: [AVAssetWriterInput] = []
        if let existingMix {
            audioInputs.append(try await passthrough(existingMix.track, name: existingMix.name ?? mixName))
        } else if let mix = options.mix, sources.count >= 2 {
            audioInputs.append(addMix(of: sources.map(\.track), settings: mix, reader: reader, writer: writer, pumps: &pumps))
        }
        for source in sources {
            audioInputs.append(try await passthrough(source.track, name: source.name))
        }

        // One alternate group: players play only the default (mix) track instead of
        // every track on top of each other; editors still see all of them.
        if audioInputs.count >= 2 {
            let group = AVAssetWriterInputGroup(inputs: audioInputs, defaultInput: audioInputs[0])
            if writer.canAdd(group) { writer.add(group) }
        }

        if let videoInput, !chapters.isEmpty {
            addChapters(chapters, range: range, to: writer, videoInput: videoInput, pumps: &pumps)
        }

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: range.start)

        await withTaskGroup(of: Void.self) { tasks in
            for pump in pumps {
                nonisolated(unsafe) let pump = pump
                tasks.addTask { await run(pump.next, into: pump.input, writer: writer) }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tmp)
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        guard writer.status == .writing else {  // e.g. disk full while remuxing
            try? FileManager.default.removeItem(at: tmp)
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        if options.timeRange != nil { writer.endSession(atSourceTime: range.end) }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tmp)
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    // MARK: Mix

    private static func addMix(of tracks: [AVAssetTrack], settings: MixSettings, reader: AVAssetReader,
                               writer: AVAssetWriter, pumps: inout [(next: () -> CMSampleBuffer?, input: AVAssetWriterInput)]) -> AVAssetWriterInput {
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        // ClipWriter always writes system audio before the microphone.
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = tracks.enumerated().map { i, track in
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(i == 0 ? settings.systemVolume : settings.micVolume, at: .zero)
            return params
        }
        output.audioMix = audioMix
        reader.add(output)

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ])
        input.metadata = [trackNameItem(mixName)]
        writer.add(input)

        let limiter = settings.limiter ? Limiter() : nil
        pumps.append(({
            guard let sample = output.copyNextSampleBuffer() else { return nil }
            return limiter?.process(sample) ?? sample
        }, input))
        return input
    }

    /// Peak limiter (instant attack, ~150 ms release) keeping the mix below −1 dBFS.
    private final class Limiter {
        private var gain: Float = 1
        private let ceiling: Float = 0.89
        private let release: Float = 1 - expf(-1 / (0.15 * 48_000))

        func process(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
            guard let block = sample.dataBuffer, let format = sample.formatDescription,
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return nil }
            let channels = Int(asbd.mChannelsPerFrame)
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / 4)
            _ = floats.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }

            var i = 0
            while i + channels <= floats.count {
                var peak: Float = 0
                for c in 0..<channels { peak = max(peak, abs(floats[i + c])) }
                let target: Float = peak * gain > ceiling ? ceiling / peak : 1
                gain = target < gain ? target : gain + (1 - gain) * release
                for c in 0..<channels { floats[i + c] *= gain }
                i += channels
            }

            var out: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &out) == noErr,
                  let out else { return nil }
            floats.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: out, offsetIntoDestination: 0, dataLength: length) }
            var result: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: out, formatDescription: format,
                sampleCount: CMSampleBufferGetNumSamples(sample),
                presentationTimeStamp: sample.presentationTimeStamp, packetDescriptions: nil, sampleBufferOut: &result)
            return result
        }
    }

    // MARK: Chapters

    private static func addChapters(_ chapters: [Chapter], range: CMTimeRange, to writer: AVAssetWriter,
                                    videoInput: AVAssetWriterInput,
                                    pumps: inout [(next: () -> CMSampleBuffer?, input: AVAssetWriterInput)]) {
        guard let format = chapterFormat() else { return }
        let input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.marksOutputTrackAsEnabled = false
        guard writer.canAdd(input) else { return }
        writer.add(input)
        let association = AVAssetTrack.AssociationType.chapterList.rawValue
        guard videoInput.canAddTrackAssociation(withTrackOf: input, type: association) else { return }
        videoInput.addTrackAssociation(withTrackOf: input, type: association)

        // Keep chapters inside the range; the one active at range start begins there.
        let start = range.start.seconds, end = range.end.seconds
        var kept = chapters.sorted { $0.time < $1.time }.filter { $0.time < end - 0.05 }
        if let lastBefore = kept.lastIndex(where: { $0.time <= start }) {
            kept.removeFirst(lastBefore)
            kept[0].time = start
        } else if kept.isEmpty || kept[0].time > start {
            kept.insert(Chapter(time: start, title: String(localized: "Start")), at: 0)
        }

        var samples: [CMSampleBuffer] = []
        for (i, chapter) in kept.enumerated() {
            let chapterEnd = i + 1 < kept.count ? kept[i + 1].time : end
            guard chapterEnd > chapter.time,
                  let sample = chapterSample(chapter.title, format: format,
                                             start: CMTime(seconds: chapter.time, preferredTimescale: 600),
                                             end: CMTime(seconds: chapterEnd, preferredTimescale: 600)) else { continue }
            samples.append(sample)
        }
        var iterator = samples.makeIterator()
        pumps.append(({ iterator.next() }, input))
    }

    /// Big-endian QuickTime 'text' sample description (what chapter tracks use).
    private static func chapterFormat() -> CMFormatDescription? {
        var d = Data()
        func u32(_ v: UInt32) { d.append(contentsOf: [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
        func u16(_ v: UInt16) { d.append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)]) }
        u32(0)                                  // size, patched below
        d.append(contentsOf: Array("text".utf8))
        d.append(contentsOf: [0, 0, 0, 0, 0, 0]) // reserved
        u16(1)                                  // data reference index
        u32(0)                                  // display flags
        u32(0)                                  // justification
        u16(0); u16(0); u16(0)                  // background color
        u16(0); u16(0); u16(0); u16(0)          // default text box
        u32(0); u16(0); u16(0)                  // default style: start char, height, ascent
        u16(1)                                  // font id
        d.append(0); d.append(0)                // face + filler
        u16(12)                                 // font size
        u16(0xFFFF); u16(0xFFFF); u16(0xFFFF)   // foreground color
        d.append(0)                             // empty font name (Pascal string)
        let size = UInt32(d.count)
        d.replaceSubrange(0..<4, with: [UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])

        var format: CMFormatDescription?
        d.withUnsafeBytes {
            _ = CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: nil, bigEndianTextDescriptionData: $0.bindMemory(to: UInt8.self).baseAddress!,
                size: d.count, flavor: nil, mediaType: kCMMediaType_Text, formatDescriptionOut: &format)
        }
        return format
    }

    /// QuickTime text sample: big-endian UInt16 length + UTF-8 text + 'encd' atom (UTF-8).
    private static func chapterSample(_ title: String, format: CMFormatDescription, start: CMTime, end: CMTime) -> CMSampleBuffer? {
        let text = Array(title.utf8)
        var data = Data([UInt8(text.count >> 8), UInt8(text.count & 0xFF)])
        data.append(contentsOf: text)
        data.append(contentsOf: [0, 0, 0, 12, 0x65, 0x6E, 0x63, 0x64, 0, 0, 1, 0])

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block else { return nil }
        data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
        var timing = CMSampleTimingInfo(duration: end - start, presentationTimeStamp: start, decodeTimeStamp: .invalid)
        var size = data.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                  sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                  sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        return sample
    }

    static func existingChapters(of asset: AVAsset) async -> [Chapter] {
        guard let locale = (try? await asset.load(.availableChapterLocales))?.first,
              let groups = try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])
        else { return [] }
        var result: [Chapter] = []
        for group in groups {
            let text = (try? await group.items.first?.load(.stringValue)) ?? nil
            result.append(Chapter(time: group.timeRange.start.seconds, title: text ?? String(localized: "Chapter")))
        }
        return result
    }

    // MARK: Helpers

    static func trackName(_ track: AVAssetTrack) async -> String? {
        guard let items = try? await track.load(.metadata) else { return nil }
        let name = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeUserDataTrackName).first
        return (try? await name?.load(.stringValue)) ?? nil
    }

    static func trackNameItem(_ name: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeUserDataTrackName
        item.value = name as NSString
        return item
    }

    static func run(_ next: @escaping () -> CMSampleBuffer?, into input: AVAssetWriterInput,
                    writer: AVAssetWriter) async {
        let queue = DispatchQueue(label: "ClipRecorder.remux.pump")
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let next = next
        nonisolated(unsafe) let writer = writer
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {
                guard !finished else { return }
                finished = true
                if writer.status == .writing { input.markAsFinished() }
                done.resume()
            }
            input.requestMediaDataWhenReady(on: queue) {
                while !finished, input.isReadyForMoreMediaData {
                    if let sample = next(), input.append(sample) { continue }
                    finish()
                }
            }
            // If the writer fails or is cancelled, the other inputs never get another
            // callback – check now and then so the pump can't hang forever.
            let watchdog = DispatchSource.makeTimerSource(queue: queue)
            watchdog.schedule(deadline: .now() + 0.5, repeating: 0.5)
            watchdog.setEventHandler {
                if finished { watchdog.cancel(); return }
                if writer.status != .writing { finish(); watchdog.cancel() }
            }
            watchdog.resume()
        }
    }
}
