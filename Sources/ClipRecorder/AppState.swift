import AppKit
import AVFoundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case starting
        case buffering
        case recording(since: Date)
        case paused(String)
        case failed(String)
    }

    // MARK: Live state

    @Published var status: Status = .starting
    @Published var sourceName = "—"
    @Published var now = Date()
    @Published var recentClips: [URL] = []
    @Published var message: String?
    @Published var markerCount = 0
    @Published var isFinalizing = false
    /// Export progress (0…1) per clip.
    @Published var exports: [URL: Double] = [:]
    @Published private(set) var microphones: [Microphones.Device] = []
    @Published private(set) var activeMic: Microphones.Device?
    @Published private(set) var hotKeyConflicts: Set<HotKeyCenter.Action> = []

    // MARK: Recording settings

    @Published var source: CaptureSettings.Source { didSet { Defaults.save(source, "source"); pushCapture() } }
    @Published var maxHeight: Int { didSet { save(maxHeight, "maxHeight"); pushCapture() } }
    @Published var fps: Int { didSet { save(fps, "fps"); pushCapture() } }
    @Published var quality: CaptureSettings.Quality { didSet { save(quality.rawValue, "quality"); pushCapture() } }
    @Published var bufferSeconds: Int { didSet { save(bufferSeconds, "bufferSeconds"); pushCapture() } }
    @Published var includeSystemAudio: Bool { didSet { save(includeSystemAudio, "includeSystemAudio"); pushCapture() } }
    @Published var includeMic: Bool { didSet { save(includeMic, "includeMic"); pushCapture() } }
    @Published var micSelection: String { didSet { save(micSelection, "micSelection"); applyMicDevice() } }
    @Published var excludedBundleIDs: [String] { didSet { save(excludedBundleIDs, "excludedBundleIDs"); pushCapture() } }

    // MARK: Mix settings

    @Published var mixSystemVolume: Double { didSet { save(mixSystemVolume, "mixSystemVolume") } }
    @Published var mixMicVolume: Double { didSet { save(mixMicVolume, "mixMicVolume") } }
    @Published var limiter: Bool { didSet { save(limiter, "limiter") } }

    // MARK: Shortcuts

    @Published var toggleCombo: KeyCombo? { didSet { Defaults.save(toggleCombo, "toggleCombo"); registerHotKeys() } }
    @Published var instantCombo: KeyCombo? { didSet { Defaults.save(instantCombo, "instantCombo"); registerHotKeys() } }
    @Published var markerCombo: KeyCombo? { didSet { Defaults.save(markerCombo, "markerCombo"); registerHotKeys() } }

    // MARK: General

    @Published var clipsDirectory: URL { didSet { save(clipsDirectory.path, "clipsDirectory"); engine.setClipsDirectory(clipsDirectory); loadRecentClips() } }
    @Published var cleanupDays: Int { didSet { save(cleanupDays, "cleanupDays"); runCleanup() } }
    @Published var cleanupGB: Int { didSet { save(cleanupGB, "cleanupGB"); runCleanup() } }
    @Published var soundsEnabled: Bool { didSet { save(soundsEnabled, "soundsEnabled") } }
    @Published var showPreview: Bool { didSet { save(showPreview, "showPreview") } }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    // MARK: Power

    @Published var userPaused: Bool { didSet { save(userPaused, "userPaused"); updateRunning() } }
    @Published var pauseOnBattery: Bool { didSet { save(pauseOnBattery, "pauseOnBattery"); updateRunning() } }
    @Published var pauseOnLowPower: Bool { didSet { save(pauseOnLowPower, "pauseOnLowPower"); updateRunning() } }

    /// Hooks for the AppKit layer.
    var onClipReady: ((URL) -> Void)?
    var onOpenSettings: (() -> Void)?

    let engine = CaptureEngine()
    /// Separate object so 15 Hz meter updates don't re-render the whole UI.
    let levels = AudioLevels()
    private var ticker: Timer?
    private var messageTask: Task<Void, Never>?
    private var deviceObservers: [Any] = []
    private var hasStarted = false

    // MARK: Derived

    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = status { return true }
        return false
    }

    var elapsed: TimeInterval {
        if case .recording(let since) = status { return max(0, now.timeIntervalSince(since)) }
        return 0
    }

    var bufferLabel: String { Self.durationLabel(bufferSeconds) }

    var mixSettings: MixSettings {
        MixSettings(systemVolume: Float(mixSystemVolume), micVolume: Float(mixMicVolume), limiter: limiter)
    }

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "maxHeight": 0, "fps": 60, "quality": "medium", "bufferSeconds": 60,
            "includeSystemAudio": true, "includeMic": true,
            "mixSystemVolume": 1.0, "mixMicVolume": 1.0, "limiter": true,
            "cleanupDays": 0, "cleanupGB": 0, "soundsEnabled": true, "showPreview": true,
            "userPaused": false, "pauseOnBattery": false, "pauseOnLowPower": true,
        ])
        source = Defaults.load("source", as: CaptureSettings.Source.self) ?? .mainDisplay
        maxHeight = d.integer(forKey: "maxHeight")
        fps = d.integer(forKey: "fps")
        quality = CaptureSettings.Quality(rawValue: d.string(forKey: "quality") ?? "") ?? .medium
        bufferSeconds = d.integer(forKey: "bufferSeconds")
        includeSystemAudio = d.bool(forKey: "includeSystemAudio")
        includeMic = d.bool(forKey: "includeMic")
        micSelection = d.string(forKey: "micSelection") ?? Microphones.auto
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        mixSystemVolume = d.double(forKey: "mixSystemVolume")
        mixMicVolume = d.double(forKey: "mixMicVolume")
        limiter = d.bool(forKey: "limiter")
        // Migrate the old preset-based setting; otherwise use the defaults.
        toggleCombo = d.object(forKey: "toggleCombo") == nil ? .defaultToggle : Defaults.load("toggleCombo", as: KeyCombo?.self) ?? nil
        instantCombo = d.object(forKey: "instantCombo") == nil ? .defaultInstant : Defaults.load("instantCombo", as: KeyCombo?.self) ?? nil
        markerCombo = d.object(forKey: "markerCombo") == nil ? .defaultMarker : Defaults.load("markerCombo", as: KeyCombo?.self) ?? nil
        clipsDirectory = d.string(forKey: "clipsDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? ClipLibrary.defaultDirectory
        cleanupDays = d.integer(forKey: "cleanupDays")
        cleanupGB = d.integer(forKey: "cleanupGB")
        soundsEnabled = d.bool(forKey: "soundsEnabled")
        showPreview = d.bool(forKey: "showPreview")
        userPaused = d.bool(forKey: "userPaused")
        pauseOnBattery = d.bool(forKey: "pauseOnBattery")
        pauseOnLowPower = d.bool(forKey: "pauseOnLowPower")

        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        engine.setClipsDirectory(clipsDirectory)
        applyMicDevice()  // also pushes capture settings
        deviceObservers = Microphones.observeChanges { [weak self] in
            MainActor.assumeIsolated { self?.applyMicDevice() }
        }
        PowerMonitor.shared.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.updateRunning() }
        }
        loadRecentClips()
        wireEngine()
        registerHotKeys()
    }

    private func wireEngine() {
        engine.onCaptureRunning = { [weak self] name in
            guard let self else { return }
            self.sourceName = name
            if !self.isRecording { self.status = .buffering }
        }
        engine.onRecordingStarted = { [weak self] buffered in
            guard let self else { return }
            self.status = .recording(since: Date().addingTimeInterval(-buffered))
            self.markerCount = 0
            self.startTicker()
            self.play("Tink")
        }
        engine.onRecordingStopped = { [weak self] in
            guard let self else { return }
            if self.isRecording { self.status = .buffering }
            self.stopTicker()
            self.isFinalizing = true
            self.flash("Zapisywanie klipu…")
        }
        engine.onMarkerAdded = { [weak self] count in
            self?.markerCount = count
            self?.play("Pop")
        }
        engine.onClipWritten = { [weak self] url, chapters in
            guard let self else { return }
            self.isFinalizing = true
            let options = ClipFinalizer.Options(mix: self.mixSettings, chapters: chapters)
            Task {
                do {
                    try await ClipFinalizer.process(url, options: options)
                } catch {
                    NSLog("ClipRecorder: finalizing failed, keeping raw clip: \(error)")
                }
                self.isFinalizing = false
                self.clipSaved(url)
            }
        }
        engine.onLevels = { [weak self] system, mic in
            self?.levels.update(system: system, mic: mic)
        }
        engine.onCaptureStopped = { [weak self] in
            guard let self else { return }
            self.levels.update(system: 0, mic: 0)
            if self.isRecording { self.status = .starting; self.stopTicker() }
        }
        engine.onError = { [weak self] text in
            guard let self else { return }
            self.flash(text)
            self.play("Basso")
        }
    }

    // MARK: Lifecycle

    func start() {
        hasStarted = true
        Task {
            await AVCapturePermission.requestMicrophone()
            applyMicDevice()  // device list is empty until mic access is granted
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                status = .failed("Brak dostępu do nagrywania ekranu. Włącz ClipRecorder w Ustawienia systemowe → Prywatność i ochrona → Nagrywanie ekranu i dźwięku systemowego, potem uruchom aplikację ponownie.")
                return
            }
            if case .failed = status { status = .starting }
            updateRunning()
        }
    }

    /// Starts or pauses the buffer depending on the user's pause and power settings.
    private func updateRunning() {
        guard hasStarted else { return }
        if case .failed = status { return }
        let power = PowerMonitor.shared
        let reason: String?
        if userPaused {
            reason = "Bufor wstrzymany"
        } else if pauseOnLowPower && power.isLowPowerMode {
            reason = "Wstrzymany – tryb niskiego zużycia energii"
        } else if pauseOnBattery && power.isOnBattery {
            reason = "Wstrzymany – zasilanie z baterii"
        } else {
            reason = nil
        }
        if let reason {
            if !isPaused { engine.stop() }
            stopTicker()
            status = .paused(reason)
        } else if isPaused || status == .starting {
            status = .starting
            engine.start()
        }
    }

    private func pushCapture() {
        engine.apply(CaptureSettings(
            source: source, maxHeight: maxHeight, fps: fps, quality: quality, bufferSeconds: bufferSeconds,
            includeSystemAudio: includeSystemAudio, includeMic: includeMic, micDeviceID: activeMic?.id,
            excludedBundleIDs: excludedBundleIDs))
    }

    private func applyMicDevice() {
        microphones = Microphones.all()
        activeMic = Microphones.resolve(micSelection, in: microphones)
        pushCapture()
    }

    // MARK: Clip actions

    func toggleClip() { engine.toggleClip() }
    func saveInstantClip() { engine.saveInstantClip() }
    func addMarker() { engine.addMarker() }
    func togglePause() { userPaused.toggle() }
    func openSettings() { onOpenSettings?() }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openClipsFolder() { NSWorkspace.shared.open(clipsDirectory) }

    func copyToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    func delete(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            recentClips.removeAll { $0 == url }
            flash("Przeniesiono do Kosza: \(url.deletingPathExtension().lastPathComponent)")
        } catch {
            flash("Nie udało się usunąć: \(error.localizedDescription)")
        }
    }

    func export(_ url: URL, target: ShareExporter.Target) {
        guard exports[url] == nil else { return }
        exports[url] = 0
        Task {
            do {
                let out = try await ShareExporter.export(url, target: target) { [weak self] p in
                    Task { @MainActor in if self?.exports[url] != nil { self?.exports[url] = p } }
                }
                exports[url] = nil
                copyToPasteboard(out)
                let mb = Double((try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
                flash(String(format: "MP4 gotowy (%.1f MB) – skopiowany do schowka, wklej go np. w Discordzie.", mb))
                play("Glass")
            } catch {
                exports[url] = nil
                flash("Eksport nie powiódł się: \(error.localizedDescription)")
                play("Basso")
            }
        }
    }

    func trim(_ url: URL) {
        TrimWindowController.show(url) { [weak self] range in
            guard let self else { return }
            self.isFinalizing = true
            self.flash("Przycinanie…")
            Task {
                do {
                    try await ClipFinalizer.process(url, options: .init(mix: nil, chapters: nil, timeRange: range))
                    self.flash("Przycięto do \(formatDuration(range.duration.seconds)).")
                    self.onClipReady?(url)
                } catch {
                    self.flash("Przycinanie nie powiodło się: \(error.localizedDescription)")
                }
                self.isFinalizing = false
            }
        }
    }

    // MARK: Settings helpers

    struct AppChoice: Identifiable, Hashable {
        let id: String  // bundle ID
        let name: String
        let icon: NSImage?
    }

    var runningApps: [AppChoice] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
                return AppChoice(id: id, name: app.localizedName ?? id, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var displays: [(id: CGDirectDisplayID, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }
    }

    func chooseClipsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = clipsDirectory
        panel.prompt = "Wybierz"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { clipsDirectory = url }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            flash("Nie udało się zmienić logowania: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func combo(for action: HotKeyCenter.Action) -> KeyCombo? {
        switch action {
        case .toggleClip: return toggleCombo
        case .instantClip: return instantCombo
        case .marker: return markerCombo
        }
    }

    func setCombo(_ combo: KeyCombo?, for action: HotKeyCenter.Action) {
        switch action {
        case .toggleClip: toggleCombo = combo
        case .instantClip: instantCombo = combo
        case .marker: markerCombo = combo
        }
    }

    // MARK: Private

    private func clipSaved(_ url: URL) {
        recentClips.removeAll { $0 == url }
        recentClips.insert(url, at: 0)
        recentClips = Array(recentClips.prefix(5))
        flash("Zapisano: \(url.deletingPathExtension().lastPathComponent)")
        play("Glass")
        runCleanup(protecting: [url])
        if showPreview { onClipReady?(url) }
    }

    private func registerHotKeys() {
        var conflicts = Set<HotKeyCenter.Action>()
        let center = HotKeyCenter.shared
        if !center.register(.toggleClip, combo: toggleCombo, handler: { [weak self] in self?.toggleClip() }) { conflicts.insert(.toggleClip) }
        if !center.register(.instantClip, combo: instantCombo, handler: { [weak self] in self?.saveInstantClip() }) { conflicts.insert(.instantClip) }
        if !center.register(.marker, combo: markerCombo, handler: { [weak self] in self?.addMarker() }) { conflicts.insert(.marker) }
        hotKeyConflicts = conflicts
    }

    private func runCleanup(protecting: Set<URL> = []) {
        guard cleanupDays > 0 || cleanupGB > 0 else { return }
        let removed = ClipLibrary.cleanup(in: clipsDirectory, maxAgeDays: cleanupDays, maxGB: cleanupGB, keeping: protecting)
        if removed > 0 {
            loadRecentClips()
            NSLog("ClipRecorder: moved \(removed) old clip(s) to Trash")
        }
    }

    private func loadRecentClips() {
        recentClips = ClipLibrary.clips(in: clipsDirectory)
            .filter { $0.url.pathExtension == "mov" }
            .prefix(5).map(\.url)
    }

    private func startTicker() {
        now = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func play(_ sound: String) {
        if soundsEnabled { NSSound(named: sound)?.play() }
    }

    private func save(_ value: Any?, _ key: String) { UserDefaults.standard.set(value, forKey: key) }

    func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { message = nil }
        }
    }

    static func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }
}

@MainActor
final class AudioLevels: ObservableObject {
    @Published private(set) var system: Float = 0
    @Published private(set) var mic: Float = 0

    func update(system: Float, mic: Float) {
        // Skip tiny changes to keep SwiftUI work low.
        if abs(system - self.system) > 0.02 || (system == 0) != (self.system == 0) { self.system = system }
        if abs(mic - self.mic) > 0.02 || (mic == 0) != (self.mic == 0) { self.mic = mic }
    }
}

enum AVCapturePermission {
    static func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }
}

func formatDuration(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    return String(format: "%02d:%02d", s / 60, s % 60)
}
