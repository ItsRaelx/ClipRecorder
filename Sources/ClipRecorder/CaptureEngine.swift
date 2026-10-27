import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

/// Captures a display (or one app's window), system audio and microphone non-stop.
/// Video is encoded to HEVC on the fly and kept (together with raw audio) in a
/// rolling buffer. A clip dumps the buffer into a new file and – unless it's an
/// instant clip – keeps appending live samples until it's stopped.
/// Thread safety: all mutable state is confined to the serial `queue`.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Track { case video, system, mic }

    // Callbacks are always delivered on the main queue.
    var onCaptureRunning: ((_ sourceName: String) -> Void)?
    var onCaptureStopped: (() -> Void)?
    var onRecordingStarted: ((_ bufferedSeconds: Double) -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onMarkerAdded: ((_ count: Int) -> Void)?
    /// Called once the clip is fully written, with the chapters to add during finalizing.
    var onClipWritten: ((_ url: URL, _ chapters: [Chapter]) -> Void)?
    var onError: ((String) -> Void)?
    /// Audio levels 0…1 (system, mic), ~15× per second.
    var onLevels: ((_ system: Float, _ mic: Float) -> Void)?

    private let queue = DispatchQueue(label: "ClipRecorder.capture", qos: .userInteractive)

    // Everything below is only touched on `queue`.
    private var settings = CaptureSettings()
    private var clipsDirectory = ClipLibrary.defaultDirectory
    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private var displayForFilter: SCDisplay?
    private var ownApps: [SCRunningApplication] = []
    private var allApps: [SCRunningApplication] = []
    private var encoder: VideoEncoder?
    private var lastPixelBuffer: CVPixelBuffer?
    private var lastEncodedPTS: CMTime = .invalid
    private var repeatTimer: DispatchSourceTimer?
    private var videoRing = SampleRing(diskDirectory: nil)
    private var systemRing = SampleRing(diskDirectory: nil)
    private var micRing = SampleRing(diskDirectory: nil)
    private var writer: ClipWriter?
    private var clipStart: CMTime = .zero
    private var chapters: [Chapter] = []
    private var isStopping = false
    private var wantsRunning = false
    private var systemLevel: Float = 0
    private var micLevel: Float = 0
    private var lastLevelReport = CMTime.zero
    private var generation = 0

    private static let diskBufferDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClipRecorder/Buffer", isDirectory: true)

    // MARK: Settings

    func apply(_ new: CaptureSettings) {
        queue.async {
            let old = self.settings
            self.settings = new
            guard self.stream != nil else { return }
            if new.needsRestart(comparedTo: old) {
                self.restart()
            } else {
                if new.micDeviceID != old.micDeviceID { self.micRing.removeAll() }  // don't mix formats of two devices
                if new.excludedBundleIDs != old.excludedBundleIDs { self.applyFilter() }
                self.applyAudioConfig()
            }
        }
    }

    func setClipsDirectory(_ url: URL) { queue.async { self.clipsDirectory = url } }

    private var micAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    /// Turning a source "Off" really stops capturing it (so the orange mic
    /// indicator disappears), not just leaves it out of the file.
    private func applyAudioConfig() {
        guard let stream, let config else { return }
        config.capturesAudio = settings.includeSystemAudio
        config.captureMicrophone = settings.includeMic && micAuthorized
        config.microphoneCaptureDeviceID = settings.micDeviceID
        if !settings.includeSystemAudio { systemRing.removeAll() }
        if !config.captureMicrophone { micRing.removeAll() }
        stream.updateConfiguration(config) { error in
            if let error { NSLog("ClipRecorder: updateConfiguration failed: \(error)") }
        }
    }

    private func applyFilter() {
        guard let stream, let display = displayForFilter else { return }
        stream.updateContentFilter(makeDisplayFilter(display)) { error in
            if let error { NSLog("ClipRecorder: updateContentFilter failed: \(error)") }
        }
    }

    private func makeDisplayFilter(_ display: SCDisplay) -> SCContentFilter {
        let excluded = ownApps + allApps.filter { settings.excludedBundleIDs.contains($0.bundleIdentifier) }
        return SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
    }

    // MARK: Capture lifecycle

    /// Starts capturing (no-op if already running).
    func start() {
        queue.async {
            self.wantsRunning = true
            guard self.stream == nil else { return }
            self.generation += 1
            let generation = self.generation
            let settings = self.settings
            Task {
                do {
                    try await self.startStream(settings: settings, generation: generation)
                } catch {
                    self.report("Nie udało się uruchomić nagrywania: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stops capturing and drops the buffer (pause / power saving).
    func stop() {
        queue.async {
            self.wantsRunning = false
            self.generation += 1
            self.stopStream()
        }
    }

    private func restart() {
        stopStream()
        start()
    }

    private func stopStream() {
        if writer != nil { stopClip() }
        let stream = self.stream
        teardown()
        stream?.stopCapture { _ in }
        DispatchQueue.main.async { self.onCaptureStopped?() }
    }

    private func startStream(settings: CaptureSettings, generation: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }

        let filter: SCContentFilter
        let sourceName: String
        var display: SCDisplay?
        switch settings.source {
        case .app(let bundleID, let name):
            // Biggest on-screen window of the app.
            let window = content.windows
                .filter { $0.owningApplication?.bundleIdentifier == bundleID && $0.isOnScreen && $0.frame.width > 100 }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            if let window {
                filter = SCContentFilter(desktopIndependentWindow: window)
                sourceName = "Okno: \(name)"
            } else {
                display = content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
                guard let display else { throw Self.error("Nie znaleziono ekranu.") }
                filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                sourceName = "\(name) nie ma okna – nagrywam ekran"
            }
        case .mainDisplay, .display:
            var wantedID = CGMainDisplayID()
            if case .display(let id) = settings.source { wantedID = id }
            display = content.displays.first { $0.displayID == wantedID }
                ?? content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
            guard let display else { throw Self.error("Nie znaleziono ekranu.") }
            let excluded = ownApps + content.applications.filter { settings.excludedBundleIDs.contains($0.bundleIdentifier) }
            filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            sourceName = Self.screenName(display.displayID) ?? "Ekran \(display.width)×\(display.height)"
        }

        // Output size: native pixels, optionally scaled down to `maxHeight`.
        let scale = CGFloat(filter.pointPixelScale)
        var width = filter.contentRect.width * scale
        var height = filter.contentRect.height * scale
        if settings.maxHeight > 0, height > CGFloat(settings.maxHeight) {
            width = width * CGFloat(settings.maxHeight) / height
            height = CGFloat(settings.maxHeight)
        }
        let w = Int(width) & ~1, h = Int(height) & ~1
        let fps = Int32(settings.fps)

        let config = SCStreamConfiguration()
        config.width = w
        config.height = h
        config.scalesToFit = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        config.showsCursor = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.capturesAudio = settings.includeSystemAudio
        config.captureMicrophone = settings.includeMic && micAuthorized
        config.microphoneCaptureDeviceID = settings.micDeviceID

        let encoder = try VideoEncoder(width: w, height: h, fps: fps, bitsPerPixel: settings.quality.bitsPerPixel) { [weak self] sample in
            guard let self else { return }
            nonisolated(unsafe) let sample = sample
            self.queue.async { self.handleEncodedVideo(sample) }
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)

        let proceed: Bool = queue.sync {
            // A newer start/stop request superseded this one.
            guard generation == self.generation, self.wantsRunning, self.stream == nil else { return false }
            let disk = settings.buffersOnDisk ? Self.diskBufferDirectory : nil
            if disk != nil {
                try? FileManager.default.removeItem(at: Self.diskBufferDirectory)  // leftovers from a crash
            }
            self.videoRing = SampleRing(diskDirectory: disk?.appendingPathComponent("video"))
            self.systemRing = SampleRing(diskDirectory: disk?.appendingPathComponent("system"))
            self.micRing = SampleRing(diskDirectory: disk?.appendingPathComponent("mic"))
            self.encoder = encoder
            self.stream = stream
            self.config = config
            self.displayForFilter = display
            self.ownApps = ownApps
            self.allApps = content.applications
            self.startRepeatTimer()
            return true
        }
        guard proceed else { encoder.invalidate(); return }
        try await stream.startCapture()
        DispatchQueue.main.async { self.onCaptureRunning?(sourceName) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            guard stream === self.stream else { return }
            if self.writer != nil { self.stopClip() }
            self.teardown()
            self.report("Przechwytywanie przerwane: \(error.localizedDescription). Ponawiam za 3 s…")
            self.queue.asyncAfter(deadline: .now() + 3) {
                if self.wantsRunning { self.start() }
            }
        }
    }

    private func teardown() {
        repeatTimer?.cancel()
        repeatTimer = nil
        stream = nil
        config = nil
        displayForFilter = nil
        encoder?.invalidate()
        encoder = nil
        lastPixelBuffer = nil
        lastEncodedPTS = .invalid
        videoRing.removeAll()
        systemRing.removeAll()
        micRing.removeAll()
    }

    // MARK: Sample input

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid, stream === self.stream else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete,
                  let pixelBuffer = sb.imageBuffer else { return }
            lastPixelBuffer = pixelBuffer
            encode(pixelBuffer, at: sb.presentationTimeStamp)
        case .audio:
            handleAudio(sb, track: .system)
        case .microphone:
            handleAudio(sb, track: .mic)
        @unknown default:
            break
        }
    }

    private func encode(_ pixelBuffer: CVPixelBuffer, at pts: CMTime) {
        if lastEncodedPTS.isValid && pts <= lastEncodedPTS { return }
        lastEncodedPTS = pts
        encoder?.encode(pixelBuffer, pts: pts)
    }

    /// ScreenCaptureKit sends no frames while the screen is static. Re-encode the last
    /// frame periodically so the buffer always has fresh keyframes to cut from.
    private func startRepeatTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, let pb = self.lastPixelBuffer else { return }
            let now = Self.hostNow()
            if !self.lastEncodedPTS.isValid || (now - self.lastEncodedPTS).seconds > 0.5 {
                self.encode(pb, at: now)
            }
        }
        timer.resume()
        repeatTimer = timer
    }

    private func handleEncodedVideo(_ sb: CMSampleBuffer) {
        guard encoder != nil else { return }
        videoRing.append(sb, isKeyframe: sb.isKeyframe)
        videoRing.trim(olderThan: sb.presentationTimeStamp.seconds - Double(settings.bufferSeconds), keyframeAligned: true)
        writer?.append(sb, to: .video)
    }

    private func handleAudio(_ original: CMSampleBuffer, track: Track) {
        guard let sb = original.deepCopiedAudio() else { return }
        reportLevel(sb, track: track)
        let ring = track == .system ? systemRing : micRing
        ring.append(sb)
        ring.trim(olderThan: sb.presentationTimeStamp.seconds - Double(settings.bufferSeconds) - 3, keyframeAligned: false)
        writer?.append(sb, to: track)
    }

    /// Peak-hold meter: jumps up instantly, falls back smoothly.
    private func reportLevel(_ sb: CMSampleBuffer, track: Track) {
        let level = sb.audioLevel
        if track == .system { systemLevel = max(level, systemLevel * 0.85) } else { micLevel = max(level, micLevel * 0.85) }
        let now = sb.presentationTimeStamp
        guard (now - lastLevelReport).seconds > 1.0 / 15 else { return }
        lastLevelReport = now
        // Decay the track that may have stopped delivering (e.g. mic turned off).
        if !settings.includeSystemAudio { systemLevel = 0 }
        if !settings.includeMic { micLevel = 0 }
        let (s, m) = (systemLevel, micLevel)
        DispatchQueue.main.async { self.onLevels?(s, m) }
    }

    // MARK: Clips

    /// Starts a clip (buffer + live), or stops the running one.
    func toggleClip() {
        queue.async {
            if self.isStopping { return }
            if self.writer == nil { self.startClip() } else { self.stopClip() }
        }
    }

    /// Saves just the buffer, without continuing to record.
    func saveInstantClip() {
        queue.async {
            guard !self.isStopping, self.writer == nil else { return }
            if self.startClip(live: false) { self.stopClip() }
        }
    }

    func addMarker() {
        queue.async {
            guard self.writer != nil, !self.isStopping else {
                self.report("Znaczniki dodajesz w trakcie nagrywania klipu.")
                return
            }
            let count = self.chapters.filter { $0.title.hasPrefix("Znacznik") }.count + 1
            self.chapters.append(Chapter(time: (Self.hostNow() - self.clipStart).seconds, title: "Znacznik \(count)"))
            DispatchQueue.main.async { self.onMarkerAdded?(count) }
        }
    }

    @discardableResult
    private func startClip(live: Bool = true) -> Bool {
        guard let first = videoRing.first, let videoFormat = first.formatDescription else {
            report(stream == nil ? "Nagrywanie jest wstrzymane." : "Bufor jest jeszcze pusty – poczekaj chwilę po uruchomieniu.")
            return false
        }
        let start = first.pts
        let url = ClipLibrary.newClipURL(in: clipsDirectory)

        let systemFormat = settings.includeSystemAudio ? systemRing.items.last?.formatDescription : nil
        let micFormat = settings.includeMic ? micRing.items.last?.formatDescription : nil
        do {
            try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
            writer = try ClipWriter(url: url, videoFormat: videoFormat, systemFormat: systemFormat,
                                    micFormat: micFormat, startTime: start)
        } catch {
            report("Nie udało się utworzyć pliku: \(error.localizedDescription)")
            return false
        }

        // Dump the buffer in timestamp order so the writer can interleave tracks.
        var merged: [(SampleRing.Item, Track)] = videoRing.items.map { ($0, .video) }
        merged += systemRing.items.filter { $0.pts >= start }.map { ($0, .system) }
        merged += micRing.items.filter { $0.pts >= start }.map { ($0, .mic) }
        merged.sort { $0.0.pts < $1.0.pts }
        for (item, track) in merged { writer?.append(item.load, to: track) }

        let buffered = (Self.hostNow() - start).seconds
        clipStart = start
        chapters = [Chapter(time: 0, title: "Bufor")]
        if live { chapters.append(Chapter(time: buffered, title: "Start nagrywania")) }
        NSLog("ClipRecorder: clip start – video %.1f s, system %.1f s, mic %.1f s",
              videoRing.span, systemRing.span, micRing.span)
        if live { DispatchQueue.main.async { self.onRecordingStarted?(buffered) } }
        return true
    }

    private func stopClip() {
        guard let writer else { return }
        isStopping = true
        // Encode one last frame "now" so the video doesn't end before the audio.
        if let pb = lastPixelBuffer { encode(pb, at: Self.hostNow()) }
        encoder?.flush()  // blocks until the encoder output handlers have been queued
        let chapters = self.chapters
        queue.async {
            self.writer = nil
            DispatchQueue.main.async { self.onRecordingStopped?() }
            writer.finish { result in
                self.queue.async { self.isStopping = false }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let url): self.onClipWritten?(url, chapters)
                    case .failure(let error): self.onError?("Zapis klipu nie powiódł się: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.onError?(message) }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "ClipRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func hostNow() -> CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    static func screenName(_ displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }?.localizedName
    }
}

extension CMSampleBuffer {
    var isKeyframe: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return true }
        return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }
}

// MARK: - Video encoder

final class VideoEncoder {
    private var session: VTCompressionSession?
    private let output: (CMSampleBuffer) -> Void

    init(width: Int, height: Int, fps: Int32, bitsPerPixel: Double, output: @escaping (CMSampleBuffer) -> Void) throws {
        self.output = output
        let spec = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC, encoderSpecification: spec,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Nie udało się uruchomić enkodera HEVC (\(status))."])
        }
        let bitrate = min(max(Double(width * height) * Double(fps) * bitsPerPixel, 3_000_000), 50_000_000)
        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_HEVC_Main_AutoLevel,
            kVTCompressionPropertyKey_ExpectedFrameRate: fps,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: fps,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 1,
            kVTCompressionPropertyKey_AverageBitRate: Int(bitrate),
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        VTSessionSetProperties(session, propertyDictionary: props as CFDictionary)
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session else { return }
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                        duration: .invalid, frameProperties: nil, infoFlagsOut: nil) { [output] status, _, sample in
            guard status == noErr, let sample else { return }
            output(sample)
        }
    }

    func flush() {
        guard let session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    func invalidate() {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
    }
}
