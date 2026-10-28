import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon `RegisterEventHotKey` – work in the background
/// without Accessibility permission.
final class HotKeyCenter {
    enum Action: UInt32, CaseIterable {
        case toggleClip = 1
        case instantClip = 2
        case marker = 3
    }

    static let shared = HotKeyCenter()

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlers: [Action: () -> Void] = [:]
    private var combos: [Action: KeyCombo] = [:]
    /// While a shortcut is being recorded in Settings, all shortcuts are unregistered:
    /// otherwise pressing a combination that's already in use would start a clip and
    /// never reach the recorder.
    var isSuspended: Bool { suspendCount > 0 }
    private var suspendCount = 0
    /// Called after a suspension ends, so the owner can register again and pick up
    /// conflicts with other apps.
    var onResume: (() -> Void)?

    func suspend() {
        suspendCount += 1
        guard suspendCount == 1 else { return }
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        guard suspendCount == 0 else { return }
        if let onResume { onResume() } else { for (action, combo) in combos { _ = registerRef(action, combo) } }
    }

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = HotKeyCenter.Action(rawValue: id.id), !HotKeyCenter.shared.isSuspended {
                HotKeyCenter.shared.handlers[action]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers (or with `nil` removes) the shortcut for an action.
    /// Returns false when the combination is already taken by another app.
    @discardableResult
    func register(_ action: Action, combo: KeyCombo?, handler: @escaping () -> Void) -> Bool {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        handlers[action] = handler
        combos[action] = combo
        guard let combo else { return true }
        if isSuspended { return true }  // registered when the recorder finishes
        return registerRef(action, combo)
    }

    private func registerRef(_ action: Action, _ combo: KeyCombo) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: action.rawValue)  // 'CLIP'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref }
        return status == noErr
    }
}

extension KeyCombo {
    static let defaultToggle = KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))
    static let defaultInstant = KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey))
    static let defaultMarker = KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        let code = UInt32(event.keyCode)
        // Plain letters, ⇧+letter (capitals) or ⌥+letter (ą, ę, …) would hijack normal
        // typing – require ⌃ or ⌘, or ⌥⇧ together. Function keys may go alone.
        let strong = mods & UInt32(controlKey | cmdKey) != 0
            || (mods & UInt32(optionKey) != 0 && mods & UInt32(shiftKey) != 0)
        if !strong && !Self.functionKeys.keys.contains(Int(code)) { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    var label: String { keys.joined() }

    /// Individual keys, e.g. ["⌃", "⌥", "R"].
    var keys: [String] {
        var k: [String] = []
        if modifiers & UInt32(controlKey) != 0 { k.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { k.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { k.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { k.append("⌘") }
        return k + [Self.keyName(Int(keyCode))]
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: String(localized: "Space"), kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static func keyName(_ code: Int) -> String {
        if let name = functionKeys[code] ?? specialKeys[code] { return name }
        // Translate with the current keyboard layout so e.g. Polish/AZERTY show the right letter.
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return "#\(code)" }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            return length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "#\(code)"
        }
    }
}
