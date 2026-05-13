import AppKit
import Carbon

enum DisplayShortcut: UInt32, CaseIterable {
    case restore = 1, brightnessUp, brightnessDown, volumeDown, volumeUp, mute, preset1, preset2, preset3
    var keyCode: UInt32 {
        switch self {
        case .restore: return UInt32(kVK_ANSI_R)
        case .brightnessUp: return UInt32(kVK_UpArrow)
        case .brightnessDown: return UInt32(kVK_DownArrow)
        case .volumeDown: return UInt32(kVK_LeftArrow)
        case .volumeUp: return UInt32(kVK_RightArrow)
        case .mute: return UInt32(kVK_ANSI_M)
        case .preset1: return UInt32(kVK_ANSI_1)
        case .preset2: return UInt32(kVK_ANSI_2)
        case .preset3: return UInt32(kVK_ANSI_3)
        }
    }
    var title: String {
        switch self {
        case .restore: return "Restore displays"
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        case .volumeDown: return "Volume down"
        case .volumeUp: return "Volume up"
        case .mute: return "Mute / unmute"
        case .preset1: return "First preset"
        case .preset2: return "Second preset"
        case .preset3: return "Third preset"
        }
    }
    var keys: String {
        switch self {
        case .restore: return "⌃⌥⌘R"
        case .brightnessUp: return "⌃⌥⌘↑"
        case .brightnessDown: return "⌃⌥⌘↓"
        case .volumeDown: return "⌃⌥⌘←"
        case .volumeUp: return "⌃⌥⌘→"
        case .mute: return "⌃⌥⌘M"
        case .preset1: return "⌃⌥⌘1"
        case .preset2: return "⌃⌥⌘2"
        case .preset3: return "⌃⌥⌘3"
        }
    }
}

/// Registered hotkeys do not intercept arbitrary keyboard input.
@MainActor final class ShortcutController {
    private static let signature: OSType = 0x444D494E
    private var handler: EventHandlerRef?
    private var registrations: [DisplayShortcut: EventHotKeyRef] = [:]
    private var failures: [DisplayShortcut: OSStatus] = [:]
    private let perform: (DisplayShortcut) -> Void
    private let report: ([String]) -> Void

    init(perform: @escaping (DisplayShortcut) -> Void, report: @escaping ([String]) -> Void) {
        self.perform = perform; self.report = report
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x444D494E,
                  let action = DisplayShortcut(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak controller] in
                guard let controller, controller.registrations[action] != nil else { return }
                controller.perform(action)
            }
            return noErr
        }, 1, &eventType, context, &handler)
        if status == noErr { register(.restore) }
    }

    func setEverydayEnabled(_ enabled: Bool) {
        for action in DisplayShortcut.allCases where action != .restore {
            if let ref = registrations.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
            failures.removeValue(forKey: action)
            if enabled, handler != nil { register(action) }
        }
        if handler == nil { report(["Keyboard shortcuts could not start. Panel controls remain available."]); return }
        report(DisplayShortcut.allCases.compactMap { action in
            failures[action].map { "\(action.title) (\(action.keys)) could not register, possibly because another app uses it. Error \($0)." }
        })
    }

    private func register(_ action: DisplayShortcut) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(action.keyCode, UInt32(controlKey | optionKey | cmdKey),
                                        EventHotKeyID(signature: Self.signature, id: action.rawValue),
                                        GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { registrations[action] = ref }
        else { failures[action] = status }
    }
    func shutdown() {
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
