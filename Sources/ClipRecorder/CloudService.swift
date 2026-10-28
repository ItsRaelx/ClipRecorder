import AppKit
import Foundation
import Security
import SystemConfiguration

/// Account + uploads for clip.secc.me. Login uses a device-code flow: the app
/// opens the browser, the user approves it on the website, and the app receives
/// an API token (kept in the Keychain). The app never sees the password.
@MainActor
final class CloudService: ObservableObject {
    struct Account: Codable, Equatable {
        let id: String
        let name: String
        let email: String
        let username: String
        let defaultVisibility: String
    }

    /// Plan limits and current usage (from /api/me).
    struct Quota: Decodable, Equatable {
        // Sizes come as JSON numbers that may be fractional (e.g. a 0.3 GB plan),
        // so they're decoded as Double and rounded.
        struct Plan: Decodable, Equatable {
            let name: String
            let expiresAt: Double?
            let maxClipBytes: Int64
            let storageBytes: Int64
            let uploadsPerDay: Int

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                expiresAt = try c.decodeIfPresent(Double.self, forKey: .expiresAt)
                maxClipBytes = Int64(try c.decode(Double.self, forKey: .maxClipBytes))
                storageBytes = Int64(try c.decode(Double.self, forKey: .storageBytes))
                uploadsPerDay = Int(try c.decode(Double.self, forKey: .uploadsPerDay))
            }
            private enum CodingKeys: String, CodingKey { case name, expiresAt, maxClipBytes, storageBytes, uploadsPerDay }
        }
        struct Usage: Decodable, Equatable {
            let bytes: Int64
            let uploadsToday: Int

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                bytes = Int64(try c.decode(Double.self, forKey: .bytes))
                uploadsToday = Int(try c.decode(Double.self, forKey: .uploadsToday))
            }
            private enum CodingKeys: String, CodingKey { case bytes, uploadsToday }
        }
        let plan: Plan
        let usage: Usage
    }

    struct PendingLogin: Equatable {
        let userCode: String
        let verificationURL: URL
    }

    enum Visibility: String, CaseIterable, Identifiable {
        case account, `public`, unlisted, `private`
        var id: String { rawValue }
        var label: String {
            switch self {
            case .account: return "Jak na koncie"
            case .public: return "Publiczne"
            case .unlisted: return "Tylko z linkiem"
            case .private: return "Prywatne"
            }
        }
    }

    struct CloudError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// From the `ClipRecorderCloudServer` Info.plist key (forks can point at their own instance).
    static let defaultServer = Bundle.main.object(forInfoDictionaryKey: "ClipRecorderCloudServer") as? String ?? "https://clip.secc.me"

    @Published private(set) var account: Account?
    @Published private(set) var pendingLogin: PendingLogin?
    @Published private(set) var quota: Quota?
    /// Share links of local clips (file path → page URL), so sharing twice just copies.
    @Published private(set) var links: [String: URL] = [:]

    @Published var server: String { didSet { UserDefaults.standard.set(server, forKey: "cloudServer"); serverChanged(oldValue) } }
    @Published var visibility: Visibility { didSet { UserDefaults.standard.set(visibility.rawValue, forKey: "cloudVisibility") } }
    @Published var autoShare: Bool { didSet { UserDefaults.standard.set(autoShare, forKey: "cloudAutoShare") } }

    /// Opens the login page (replaceable in tests).
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var isSignedIn: Bool { account != nil }
    var serverHost: String { baseURL?.host() ?? server }

    private var loginTask: Task<Void, Never>?
    /// UI snapshots run outside the app bundle – they must never touch the Keychain
    /// (that would show "ClipRecorder wants to use confidential information" prompts).
    nonisolated(unsafe) static var offline = false

    /// Snapshots only: shows a signed-in account and/or a pending login without the network.
    func preview(account: Account?, quotaJSON: String? = nil, pendingLogin: PendingLogin? = nil) {
        guard Self.offline else { return }
        self.account = account
        self.quota = quotaJSON.flatMap { try? JSONDecoder().decode(Quota.self, from: Data($0.utf8)) }
        self.pendingLogin = pendingLogin
    }
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init() {
        let d = UserDefaults.standard
        server = d.string(forKey: "cloudServer") ?? Self.defaultServer
        visibility = Visibility(rawValue: d.string(forKey: "cloudVisibility") ?? "") ?? .account
        autoShare = d.bool(forKey: "cloudAutoShare")
        account = Defaults.load("cloudAccount", as: Account.self)
        links = (d.dictionary(forKey: "cloudLinks") as? [String: String] ?? [:])
            .compactMapValues { URL(string: $0) }.filter { Self.isWebURL($0.value) }
        pruneLinks()
        guard !Self.offline else { return }
        // Only a token that's really gone means signed out – a Keychain that can't be
        // read right now (prompt pending, screen locked) keeps the account.
        // One read at launch (each read may show an access prompt after an update).
        if token != nil {
            Task { await refreshAccount() }
        } else if !keychainUnavailable {
            account = nil
        }
    }

    /// Only http(s) links from the server may be opened (never file:// or app schemes).
    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host() != nil
    }

    private var baseURL: URL? {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
    }

    /// In-memory copy, so a Keychain hiccup can't mix up accounts during a session.
    private var cachedToken: (server: String, token: String?)?
    /// The last Keychain read was refused (e.g. the access prompt was dismissed).
    private var keychainUnavailable = false

    private var token: String? {
        if Self.offline { return nil }
        if let cachedToken, cachedToken.server == server { return cachedToken.token }
        switch Keychain.token(for: server) {
        case .found(let token):
            keychainUnavailable = false
            cachedToken = (server, token)
            return token
        case .notFound:
            keychainUnavailable = false
            cachedToken = (server, nil)
            return nil
        case .unavailable:
            keychainUnavailable = true  // not cached: ask again next time
            return nil
        }
    }

    private func storeToken(_ token: String?) {
        cachedToken = (server, token)
        if let token { Keychain.setToken(token, for: server) } else { Keychain.deleteToken(for: server) }
    }

    private func serverChanged(_ old: String) {
        guard old != server else { return }
        cancelLogin()
        setAccount(nil)
        Task { await refreshAccount() }
    }

    // MARK: Login (device code)

    func startLogin() {
        cancelLogin()
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let device = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
                let start: DeviceStart = try await self.request("POST", "/api/device/start", json: ["deviceName": "ClipRecorder – \(device)", "platform": "macos"])
                // Only web pages – a misbehaving server must not make us open e.g. a file:// URL.
                guard let url = URL(string: start.verificationUrl), Self.isWebURL(url) else {
                    throw CloudError(message: "Serwer zwrócił zły adres logowania.")
                }
                self.pendingLogin = PendingLogin(userCode: start.userCode, verificationURL: url)
                self.openURL(url)

                let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
                while !Task.isCancelled, Date() < deadline {
                    try await Task.sleep(for: .seconds(max(1, start.interval)))
                    let poll: DevicePoll
                    do {
                        poll = try await self.request("POST", "/api/device/poll", json: ["deviceCode": start.deviceCode])
                    } catch let error as HTTPError where error.status == 429 || error.status >= 500 {
                        continue  // busy server – the code in the browser is still valid
                    } catch is CloudError {
                        continue  // short network blip
                    }
                    try Task.checkCancellation()
                    switch poll.status {
                    case "pending":
                        continue
                    case "approved":
                        guard let token = poll.token, let account = poll.account else { throw CloudError(message: "Niepełna odpowiedź serwera.") }
                        self.storeToken(token)
                        self.setAccount(account)
                        await self.refreshAccount()  // plan + usage
                        self.pendingLogin = nil
                        NSApp?.activate(ignoringOtherApps: true)
                        return
                    case "denied":
                        throw CloudError(message: "Logowanie odrzucone.")
                    default:
                        throw CloudError(message: "Kod logowania wygasł. Spróbuj ponownie.")
                    }
                }
                if !Task.isCancelled { throw CloudError(message: "Kod logowania wygasł. Spróbuj ponownie.") }
            } catch {
                // Cancelled (also mid-request): a newer login may already own pendingLogin.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.pendingLogin = nil
                self.onError?(error.localizedDescription)
            }
        }
    }

    func reopenLoginPage() {
        if let url = pendingLogin?.verificationURL { openURL(url) }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        pendingLogin = nil
    }

    func signOut() {
        let token = self.token
        storeToken(nil)
        setAccount(nil)
        guard let token else { return }
        Task { _ = try? await self.rawRequest("DELETE", "/api/me", token: token) }
    }

    func refreshAccount() async {
        guard let token else {
            if !keychainUnavailable { setAccount(nil) }
            return
        }
        let server = self.server
        // Signed out or switched servers while waiting → this answer is stale.
        func stillCurrent() -> Bool { self.server == server && self.token == token }
        do {
            let data = try await rawRequest("GET", "/api/me", token: token)
            guard stillCurrent() else { return }
            let me = try JSONDecoder().decode(Me.self, from: data)
            setAccount(me.account)
            quota = try? JSONDecoder().decode(QuotaEnvelope.self, from: data).account
            retryOrphanCleanup(token: token)
        } catch let error as HTTPError where error.status == 401 {
            guard stillCurrent() else { return }
            storeToken(nil)
            setAccount(nil)
        } catch {
            // Offline – keep the cached account.
        }
    }

    func openDashboard() {
        if let url = baseURL?.appending(path: "dashboard") { NSWorkspace.shared.open(url) }
    }

    func openPricing() {
        if let url = baseURL?.appendingPathComponent("pricing") { NSWorkspace.shared.open(url) }
    }

    func openSignUp() {
        if let url = baseURL?.appending(path: "register") { NSWorkspace.shared.open(url) }
    }

    /// Called with user-facing error messages (shown as a toast by AppState).
    var onError: ((String) -> Void)?

    private func setAccount(_ account: Account?) {
        self.account = account
        if account == nil { quota = nil }
        if let account { Defaults.save(account, "cloudAccount") } else { UserDefaults.standard.removeObject(forKey: "cloudAccount") }
    }

    // MARK: Upload

    struct UploadInfo {
        var title: String
        var duration: Double
        var width: Int?
        var height: Int?
        var thumbnail: Data?
    }

    func link(for clip: URL) -> URL? { links[clip.path] }

    func rememberLink(_ link: URL, for clip: URL) {
        links[clip.path] = link
        UserDefaults.standard.set(links.mapValues(\.absoluteString), forKey: "cloudLinks")
    }

    func forgetLink(for clip: URL) {
        guard links[clip.path] != nil else { return }
        links[clip.path] = nil
        UserDefaults.standard.set(links.mapValues(\.absoluteString), forKey: "cloudLinks")
    }

    /// Drops links of clips that no longer exist (deleted, cleaned up, moved).
    func pruneLinks() {
        // Keep links whose folder isn't reachable (e.g. an external disk that isn't mounted yet).
        let files = FileManager.default
        let alive = links.filter { path, _ in
            files.fileExists(atPath: path) || !files.fileExists(atPath: (path as NSString).deletingLastPathComponent)
        }
        guard alive.count != links.count else { return }
        links = alive
        UserDefaults.standard.set(links.mapValues(\.absoluteString), forKey: "cloudLinks")
    }

    /// Uploads an MP4 in parts (as the server asks) and returns the share page URL.
    func upload(_ file: URL, info: UploadInfo, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        // One token for the whole upload, so signing out midway can't mix accounts.
        guard let token else {
            throw CloudError(message: keychainUnavailable
                ? "Nie udało się odczytać logowania z pęku kluczy. Zezwól ClipRecorder na dostęp i spróbuj ponownie."
                : "Zaloguj się, aby udostępniać klipy.")
        }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var body: [String: Any] = [
            "title": info.title, "size": size, "duration": info.duration,
            "contentType": "video/mp4", "source": "app",
        ]
        if let w = info.width, let h = info.height { body["width"] = w; body["height"] = h }
        if visibility != .account { body["visibility"] = visibility.rawValue }
        let clip: CreatedClip = try await request("POST", "/api/clips", json: body, token: token)

        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var sent = 0
            for part in 1...max(1, clip.parts) {
                try Task.checkCancellation()
                try handle.seek(toOffset: UInt64((part - 1) * clip.partSize))
                guard let chunk = try handle.read(upToCount: clip.partSize), !chunk.isEmpty else { break }
                let base = sent
                try await withRetry {
                    try await self.put("/api/clips/\(clip.id)/parts/\(part)", data: chunk, contentType: "application/octet-stream", token: token) { bytes in
                        progress(Double(base + bytes) / Double(max(size, 1)))
                    }
                }
                sent += chunk.count
                progress(Double(sent) / Double(max(size, 1)))
            }
            if let thumb = info.thumbnail {
                try? await put("/api/clips/\(clip.id)/thumbnail", data: thumb, contentType: "image/jpeg", token: token, progress: nil)
            }
            let done: Completed = try await request("POST", "/api/clips/\(clip.id)/complete", token: token)
            guard let url = URL(string: done.url), Self.isWebURL(url) else { throw CloudError(message: "Serwer zwrócił zły link.") }
            return url
        } catch {
            // Separate task: if we were cancelled, a request made here would be cancelled too.
            // A half-uploaded clip counts against the account's limits, so if deleting it
            // fails (offline) it's remembered and retried later.
            let server = self.server
            Task {
                do { try await self.rawRequest("DELETE", "/api/clips/\(clip.id)", token: token) } catch {
                    self.rememberOrphan(clip.id, server: server)
                }
            }
            throw error
        }
    }

    // MARK: Unfinished uploads

    private var orphans: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: "cloudOrphans") as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "cloudOrphans") }
    }

    private func rememberOrphan(_ id: String, server: String) {
        orphans[server, default: []].append(id)
    }

    private func retryOrphanCleanup(token: String) {
        let server = self.server
        guard let ids = orphans[server], !ids.isEmpty else { return }
        Task {
            for id in ids {
                do {
                    try await self.rawRequest("DELETE", "/api/clips/\(id)", token: token)
                } catch let error as HTTPError where (400..<500).contains(error.status) {
                    // Already gone (or not ours any more) – nothing to retry.
                } catch {
                    continue
                }
                self.orphans[server]?.removeAll { $0 == id }
            }
        }
    }

    private func withRetry(_ attempt: () async throws -> Void) async throws {
        var tries = 0
        while true {
            do { return try await attempt() } catch {
                tries += 1
                if tries >= 3 || error is CancellationError || (error as? HTTPError).map({ (400..<500).contains($0.status) }) == true {
                    throw error
                }
                try await Task.sleep(for: .seconds(Double(tries)))
            }
        }
    }

    // MARK: HTTP

    struct HTTPError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private struct DeviceStart: Decodable { let deviceCode, userCode, verificationUrl: String; let interval, expiresIn: Int }
    private struct DevicePoll: Decodable { let status: String; let token: String?; let account: Account? }
    private struct QuotaEnvelope: Decodable { let account: Quota }
    private struct Me: Decodable { let account: Account }
    private struct CreatedClip: Decodable { let id, slug, url: String; let partSize, parts: Int }
    private struct Completed: Decodable { let url: String }
    private struct ServerMessage: Decodable { let error: String? }

    private func makeRequest(_ method: String, _ path: String, token: String?) throws -> URLRequest {
        guard let base = baseURL, base.host() != nil else {
            throw CloudError(message: "Nieprawidłowy adres serwera: \(server)")
        }
        // Appended (not resolved) so a server under a sub-path (https://host/clips) keeps it.
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        request.setValue("ClipRecorder/\(version) (macOS)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func check(_ data: Data, _ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.error
                ?? (status == 0 ? "Brak połączenia z serwerem." : "Błąd serwera. Spróbuj później.")
            throw HTTPError(status: status, message: message)
        }
    }

    @discardableResult
    private func rawRequest(_ method: String, _ path: String, json: [String: Any]? = nil, token: String?) async throws -> Data {
        var request = try makeRequest(method, path, token: token)
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, response) = try await session.data(for: request)
            try check(data, response)
            return data
        } catch let error as URLError {
            throw Self.describe(error, fallback: "Brak połączenia z serwerem.")
        }
    }

    /// Readable message for a network failure (cancellation stays a cancellation).
    private static func describe(_ error: URLError, fallback: String) -> Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return CloudError(message: "Serwer nie odpowiada. Spróbuj później.")
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
            return CloudError(message: "Nie da się bezpiecznie połączyć z serwerem. Sprawdź jego adres.")
        case .cannotFindHost, .dnsLookupFailed:
            return CloudError(message: "Nie znaleziono serwera. Sprawdź jego adres.")
        default:
            return CloudError(message: fallback)
        }
    }

    private func request<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil, token: String? = nil) async throws -> T {
        let data = try await rawRequest(method, path, json: json, token: token)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CloudError(message: "Nieoczekiwana odpowiedź serwera. Sprawdź jego adres.")
        }
    }

    private func put(_ path: String, data: Data, contentType: String, token: String, progress: (@MainActor (Int) -> Void)?) async throws {
        var request = try makeRequest("PUT", path, token: token)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        let delegate = UploadProgressDelegate { sent in
            Task { @MainActor in progress?(Int(sent)) }
        }
        do {
            let (body, response) = try await session.upload(for: request, from: data, delegate: delegate)
            try check(body, response)
        } catch let error as URLError {
            throw Self.describe(error, fallback: "Wysyłanie przerwane. Sprawdź internet.")
        }
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: (Int64) -> Void
    init(onProgress: @escaping (Int64) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onProgress(totalBytesSent)
    }
}

/// API token storage (one generic password per server).
enum Keychain {
    private static let service = "io.github.itsraelx.ClipRecorder.cloud"

    private static func query(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: server]
    }

    enum Lookup {
        case found(String)
        case notFound
        /// Exists (maybe) but can't be read now: access denied, prompt dismissed, locked.
        case unavailable(OSStatus)
    }

    static func token(for server: String) -> Lookup {
        var q = query(server)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else { return .notFound }
            return .found(token)
        case errSecItemNotFound:
            return .notFound
        default:
            NSLog("ClipRecorder: Keychain read failed (\(status))")
            return .unavailable(status)
        }
    }

    static func setToken(_ token: String, for server: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(server) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else {
            if status != errSecSuccess { NSLog("ClipRecorder: Keychain update failed (\(status))") }
            return
        }
        var q = query(server)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        q[kSecAttrLabel as String] = "ClipRecorder – \(server)"
        let added = SecItemAdd(q as CFDictionary, nil)
        if added != errSecSuccess { NSLog("ClipRecorder: Keychain add failed (\(added))") }
    }

    static func deleteToken(for server: String) {
        let status = SecItemDelete(query(server) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { NSLog("ClipRecorder: Keychain delete failed (\(status))") }
    }
}
