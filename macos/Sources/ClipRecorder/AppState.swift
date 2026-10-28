import AppKit
import AVFoundation
import Combine
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
    /// "Udostępnij link" progress (export + upload, 0…1) per clip.
    @Published var shares: [URL: Double] = [:]
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
    @Published var checkForUpdates: Bool { didSet { save(checkForUpdates, "checkForUpdates"); updater.start(enabled: checkForUpdates) } }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    // MARK: Power

    @Published var userPaused: Bool {
        didSet {
            save(userPaused, "userPaused")
            if !userPaused { pausedUntil = nil }
            updateRunning()
        }
    }
    /// End of a timed pause ("Wstrzymaj na 15 minut"); nil = until resumed by hand.
    @Published private(set) var pausedUntil: Date? {
        didSet { save(pausedUntil, "pausedUntil"); scheduleAutoResume() }
    }
    @Published var pauseOnBattery: Bool { didSet { save(pauseOnBattery, "pauseOnBattery"); updateRunning() } }
    @Published var pauseOnLowPower: Bool { didSet { save(pauseOnLowPower, "pauseOnLowPower"); updateRunning() } }

    /// Hooks for the AppKit layer.
    var onClipReady: ((URL) -> Void)?
    var onOpenSettings: ((SettingsView.Section?) -> Void)?

    let engine = CaptureEngine()
    /// Separate object so 15 Hz meter updates don't re-render the whole UI.
    let levels = AudioLevels()
    let updater = UpdateChecker()
    /// Thumbnails and details for the recent clips list.
    let clipInfo = ClipInfoStore()
    /// clip.secc.me account and uploads.
    let cloud = CloudService()
    /// Clip to upload as soon as the browser login completes.
    private var pendingShare: URL?
    /// Running "Udostępnij link" jobs, so they can be cancelled.
    private var shareTasks: [URL: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?
    private var messageTask: Task<Void, Never>?
    private var deviceObservers: [Any] = []
    private var resumeTask: Task<Void, Never>?
    /// "Nagrywaj mimo to" while paused for battery/low power – lasts until the power state changes.
    private var ignorePowerPause = false
    /// Screen locked or asleep: macOS doesn't allow capturing then. Pause quietly and
    /// start again the moment the user is back (instead of retrying with a backoff).
    private var screenAway = false
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
        Self.migrateLegacyDefaults()
        let d = UserDefaults.standard
        d.register(defaults: [
            "checkForUpdates": true,
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
        checkForUpdates = d.bool(forKey: "checkForUpdates")
        let wasPaused = d.bool(forKey: "userPaused")
        userPaused = wasPaused
        pausedUntil = wasPaused ? d.object(forKey: "pausedUntil") as? Date : nil
        pauseOnBattery = d.bool(forKey: "pauseOnBattery")
        pauseOnLowPower = d.bool(forKey: "pauseOnLowPower")

        try? FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        engine.setClipsDirectory(clipsDirectory)
        applyMicDevice()  // also pushes capture settings
        deviceObservers = Microphones.observeChanges { [weak self] in
            MainActor.assumeIsolated { self?.applyMicDevice() }
        }
        watchScreenLock()
        // An app on the "hide in recording" list may be launched later.
        deviceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.engine.appLaunched(bundleID: id) }
        })
        PowerMonitor.shared.onChange = { [weak self] in
            MainActor.assumeIsolated {
                self?.ignorePowerPause = false
                self?.updateRunning()
            }
        }
        loadRecentClips()
        wireEngine()
        wireCloud()
        HotKeyCenter.shared.onResume = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
        updater.start(enabled: checkForUpdates)
        scheduleAutoResume()  // a timed pause may have run out while the app was closed
    }

    private func wireCloud() {
        cloud.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cloud.onError = { [weak self] text in
            self?.flash(text)
            self?.play("Basso")
        }
        // Login cancelled or failed → forget the clip that was waiting for it.
        cloud.$pendingLogin
            .removeDuplicates()
            .sink { [weak self] pending in
                guard let self, pending == nil, !self.cloud.isSignedIn else { return }
                self.pendingShare = nil
            }
            .store(in: &cancellables)
        // Only react to signing in/out – not to name or setting changes made on the website.
        cloud.$account
            .map { $0?.id }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                guard id != nil, let account = self.cloud.account else {
                    self.shareTasks.values.forEach { $0.cancel() }  // signed out → stop uploads
                    return
                }
                self.flash("Zalogowano jako \(account.name.isEmpty ? account.email : account.name).")
                if let url = self.pendingShare {
                    self.pendingShare = nil
                    self.shareLink(url)
                }
            }
            .store(in: &cancellables)
    }

    /// Settings were stored under the old bundle ID before 1.0.0 – copy them over once.
    private static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedLegacyDefaults") else { return }
        d.set(true, forKey: "migratedLegacyDefaults")
        guard let old = d.persistentDomain(forName: "com.local.ClipRecorder") else { return }
        for (key, value) in old where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
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
            self.updateRunning()  // a power pause may have been waiting for the clip to end
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
        engine.onClipFailed = { [weak self] in self?.isFinalizing = false }
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
                status = .failed("Włącz ClipRecorder w Ustawieniach systemowych → Prywatność i ochrona → Nagrywanie ekranu i dźwięku systemowego. Potem uruchom aplikację ponownie.")
                watchScreenPermission()
                return
            }
            if case .failed = status { status = .starting }
            updateRunning()
        }
    }

    /// Starts or pauses the buffer depending on the user's pause and power settings.
    private func watchScreenLock() {
        screenAway = Self.screenIsLocked
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let away: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.screensDidSleepNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
        ]
        let back: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.screensDidWakeNotification),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in away {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScreenAway(true) }
            })
        }
        for (center, name) in back {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenMayBeBack() }
            })
        }
    }

    /// Waking the display doesn't unlock it – only resume once both are true.
    private static var screenIsLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func screenMayBeBack() {
        setScreenAway(Self.screenIsLocked)
        // The session's lock flag can lag behind the notification – look again shortly.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.setScreenAway(Self.screenIsLocked)
        }
    }

    private func setScreenAway(_ away: Bool) {
        guard away != screenAway else { return }
        screenAway = away
        updateRunning()
    }

    private func updateRunning() {
        guard hasStarted else { return }
        if case .failed = status { return }
        let power = PowerMonitor.shared
        let reason: String?
        if screenAway {
            reason = "Ekran zablokowany"
        } else if userPaused, let pausedUntil {
            reason = "Wstrzymane do \(pausedUntil.formatted(date: .omitted, time: .shortened))"
        } else if userPaused {
            reason = "Wstrzymane"
        } else if ignorePowerPause {
            reason = nil
        } else if pauseOnLowPower && power.isLowPowerMode {
            reason = "Wstrzymane w trybie oszczędzania energii"
        } else if pauseOnBattery && power.isOnBattery {
            reason = "Wstrzymane na baterii"
        } else {
            reason = nil
        }
        if let reason {
            // Never cut a clip short because the charger was unplugged – pause once it's saved.
            if isRecording && !userPaused { return }
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

    /// Quitting mid-recording first saves the clip (and lets it finish processing).
    func prepareToQuit(_ done: @escaping () -> Void) {
        if isRecording { engine.toggleClip() }
        // Reply exactly once: when everything is saved, or after 20 s at the latest.
        var replied = false
        let finish = { if !replied { replied = true; done() } }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            finish()
        }
        engine.whenIdle { [weak self] in
            Task { @MainActor in
                while let self, self.isFinalizing, !replied {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                finish()
            }
        }
    }

    var needsQuitConfirmation: Bool { isRecording || isFinalizing }
    func saveInstantClip() { engine.saveInstantClip() }
    func addMarker() { engine.addMarker() }
    func togglePause() { if userPaused { resume() } else { pause(for: nil) } }

    /// Pauses the background recording, optionally only for a while.
    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { Date().addingTimeInterval($0) }
        if userPaused { updateRunning() } else { userPaused = true }
    }

    func resume() { userPaused = false }

    /// Paused because of battery / low power mode (not by the user).
    var isPowerPaused: Bool { isPaused && !userPaused && !screenAway }

    func resumeDespitePower() {
        ignorePowerPause = true
        updateRunning()
    }

    private func scheduleAutoResume() {
        resumeTask?.cancel()
        guard let pausedUntil else { return }
        resumeTask = Task { [weak self] in
            let wait = pausedUntil.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self, self.userPaused else { return }
            self.resume()
            self.flash("Nagrywanie w tle wznowione.")
        }
    }
    func openSettings(_ section: SettingsView.Section? = nil) { onOpenSettings?(section) }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func openClipsFolder() { NSWorkspace.shared.open(clipsDirectory) }

    func copyToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    func delete(_ url: URL) {
        cancelShare(url)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            recentClips.removeAll { $0 == url }
            cloud.forgetLink(for: url)
            flash("Przeniesiono do Kosza: \(url.deletingPathExtension().lastPathComponent)")
        } catch {
            flash("Nie udało się usunąć: \(error.localizedDescription)")
        }
    }

    // MARK: Sharing (clip.secc.me)

    /// Converts the clip to a web MP4, uploads it and copies the link.
    /// Not signed in → starts the browser login and shares right after it.
    func shareLink(_ url: URL) { shareLink(url, quotaRefreshed: false) }

    private func shareLink(_ url: URL, quotaRefreshed: Bool) {
        if let link = cloud.link(for: url) {
            copyLink(link)
            return
        }
        guard cloud.isSignedIn else {
            // Already waiting for the browser → keep that code (a new one would invalidate it).
            if cloud.pendingLogin == nil { cloud.startLogin() } else { cloud.reopenLoginPage() }
            pendingShare = url
            flash("Zaloguj się w przeglądarce. Potem klip wyśle się sam.")
            return
        }
        guard shares[url] == nil else { return }
        // Known limits: say so now instead of after converting the whole clip. The numbers
        // may be old (new day, space freed on the website) – refresh once before refusing.
        if let quota = cloud.quota, quotaBlocks(quota) {
            guard quotaRefreshed else {
                Task {
                    await cloud.refreshAccount()
                    shareLink(url, quotaRefreshed: true)
                }
                return
            }
            if quota.plan.uploadsPerDay > 0, quota.usage.uploadsToday >= quota.plan.uploadsPerDay {
                flash("Dzisiejszy limit wysyłek (\(quota.plan.uploadsPerDay)) jest wykorzystany.")
                play("Basso")
                return
            }
            if quota.plan.storageBytes > 0, quota.usage.bytes >= quota.plan.storageBytes {
                flash("Brak miejsca na koncie. Usuń stare klipy na stronie albo zmień plan.")
                play("Basso")
                return
            }
        }
        shares[url] = 0
        shareTasks[url] = Task {
            defer { shareTasks[url] = nil }
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipRecorder-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            do {
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                let mp4 = try await ShareExporter.export(url, to: temp) { p in
                    Task { @MainActor in if self.shares[url] != nil { self.shares[url] = p * 0.3 } }
                }
                if let quota = cloud.quota, quota.plan.maxClipBytes > 0,
                   let size = try? mp4.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) > quota.plan.maxClipBytes {
                    let limit = ByteCountFormatter.string(fromByteCount: quota.plan.maxClipBytes, countStyle: .file)
                    throw CloudService.CloudError(message: "Klip jest za duży na Twój plan (do \(limit)). Przytnij go.")
                }
                let info = await Self.uploadInfo(for: mp4, title: url.deletingPathExtension().lastPathComponent)
                let link = try await cloud.upload(mp4, info: info) { p in
                    if self.shares[url] != nil { self.shares[url] = 0.3 + p * 0.7 }
                }
                shares[url] = nil
                cloud.rememberLink(link, for: url)
                copyLink(link)
                play("Glass")
                Task { await cloud.refreshAccount() }  // updated storage usage
            } catch {
                shares[url] = nil
                if Task.isCancelled || error is CancellationError {
                    // Deleting the clip cancels too – its own toast says enough then.
                    if FileManager.default.fileExists(atPath: url.path) { flash("Anulowano udostępnianie.") }
                } else {
                    flash("Udostępnianie nie powiodło się: \(error.localizedDescription)")
                    play("Basso")
                }
            }
        }
    }

    private func quotaBlocks(_ quota: CloudService.Quota) -> Bool {
        (quota.plan.uploadsPerDay > 0 && quota.usage.uploadsToday >= quota.plan.uploadsPerDay)
            || (quota.plan.storageBytes > 0 && quota.usage.bytes >= quota.plan.storageBytes)
    }

    func cancelShare(_ url: URL) {
        shareTasks[url]?.cancel()
    }

    func copyLink(_ link: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        flash("Link skopiowany.")
    }

    func openLink(_ url: URL) {
        if let link = cloud.link(for: url) { NSWorkspace.shared.open(link) }
    }

    /// Duration, size and a JPEG frame for the clip page.
    nonisolated static func uploadInfo(for file: URL, title: String) async -> CloudService.UploadInfo {
        let asset = AVURLAsset(url: file)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        var info = CloudService.UploadInfo(title: title, duration: duration.isFinite ? duration : 0)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize) {
            info.width = Int(size.width)
            info.height = Int(size.height)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let time = CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)
        if let image = try? await generator.image(at: time).image {
            info.thumbnail = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        }
        return info
    }

    func trim(_ url: URL) {
        TrimWindowController.show(url) { [weak self] range in
            guard let self else { return }
            self.cloud.forgetLink(for: url)  // the shared copy is the untrimmed version
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

    /// Snapshots show a fixed list instead of whatever happens to run on this Mac.
    var runningAppsOverride: [AppChoice]?

    var runningApps: [AppChoice] {
        if let runningAppsOverride { return runningAppsOverride }
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

    /// macOS only applies a new screen-recording permission after a restart – once
    /// it shows up, offer that right in the card.
    @Published private(set) var permissionGranted = false
    private var permissionTask: Task<Void, Never>?

    private func watchScreenPermission() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if CGPreflightScreenCaptureAccess() {
                    self.permissionGranted = true
                    return
                }
            }
        }
    }

    /// Starts a fresh copy of the app and quits this one.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        // Wait until this process is really gone – otherwise `open` just activates it.
        task.arguments = ["-c", "while kill -0 $1 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path, String(pid)]
        try? task.run()
        NSApp.terminate(nil)
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
        // One combination can only do one thing – take it away from the other action.
        if let combo {
            for other in HotKeyCenter.Action.allCases where other != action && self.combo(for: other) == combo {
                setCombo(nil, for: other)
            }
        }
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
        if cloud.autoShare && cloud.isSignedIn { shareLink(url) }
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
            cloud.pruneLinks()
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
