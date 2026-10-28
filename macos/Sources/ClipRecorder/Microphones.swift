import AVFoundation
import CoreAudio

/// Microphone discovery. Capturing from a Bluetooth headset's mic (AirPods etc.)
/// forces it into the low-quality mono "headset/call" profile, which ruins music
/// playback, so "auto" avoids Bluetooth mics whenever a wired/built-in one exists.
enum Microphones {
    static let auto = "auto"

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let isBluetooth: Bool
        let isBuiltIn: Bool
    }

    static func all() -> [Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices
            .map(device)
    }

    /// Device to capture for the given selection (`auto` or a device uniqueID).
    static func resolve(_ selection: String, in devices: [Device]) -> Device? {
        if selection != auto, let chosen = devices.first(where: { $0.id == selection }) {
            return chosen
        }
        let systemDefault = AVCaptureDevice.default(for: .audio).map(device)
        if let systemDefault, !systemDefault.isBluetooth { return systemDefault }
        return devices.first(where: \.isBuiltIn) ?? devices.first(where: { !$0.isBluetooth }) ?? systemDefault
    }

    private static func device(_ d: AVCaptureDevice) -> Device {
        let transport = UInt32(bitPattern: d.transportType)
        return Device(
            id: d.uniqueID,
            name: d.localizedName,
            isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    /// Calls `handler` on the main queue when devices are (dis)connected or the
    /// system default input changes.
    static func observeChanges(_ handler: @escaping () -> Void) -> [Any] {
        let center = NotificationCenter.default
        var tokens: [Any] = [
            center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { _ in handler() },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { _ in handler() },
        ]
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        tokens.append(block)
        return tokens
    }
}
