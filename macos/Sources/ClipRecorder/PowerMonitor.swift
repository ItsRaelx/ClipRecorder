import Foundation
import IOKit.ps

/// Watches "on battery" and Low Power Mode so the buffer can pause to save energy.
final class PowerMonitor {
    static let shared = PowerMonitor()

    /// Fires only when "on battery" or Low Power Mode actually changes – IOKit also
    /// notifies on every battery percentage tick.
    var onChange: (() -> Void)?
    private var lastState: (battery: Bool, lowPower: Bool)?

    private func notifyIfChanged() {
        let state = (battery: isOnBattery, lowPower: isLowPowerMode)
        if let lastState, lastState == state { return }
        lastState = state
        onChange?()
    }

    var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.notifyIfChanged() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.notifyIfChanged()
        }
        lastState = (isOnBattery, isLowPowerMode)
    }
}
