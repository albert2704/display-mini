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
    static let presetActions: [Self] = [.preset1, .preset2, .preset3]
    var defaultBinding: ShortcutBinding { .init(keyCode: keyCode, modifiers: [.control, .option, .command]) }

}

@MainActor protocol HotKeyRegistering {
    func register(_ binding: ShortcutBinding, id: UInt32) -> OSStatus
    func unregister(id: UInt32)
}

@MainActor final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private var references: [UInt32: EventHotKeyRef] = [:]
    func register(_ binding: ShortcutBinding, id: UInt32) -> OSStatus {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers.carbon,
            EventHotKeyID(signature: ShortcutController.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { references[id] = ref; return noErr }
        return status == noErr ? OSStatus(eventNotHandledErr) : status
    }
    func unregister(id: UInt32) {
        if let ref = references.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}

/// New chords are acquired before old registrations are released. Failed edits preserve the active bindings.
@MainActor final class ShortcutController {
    static let signature: OSType = 0x444D494E
    private struct Registration { let id: UInt32; let action: DisplayShortcut }
    private let registrar: HotKeyRegistering
    private var handler: EventHandlerRef?
    private var handlerAvailable = false
    private var registrations: [ShortcutBinding: Registration] = [:]
    private var nextID: UInt32 = 1
    private var currentPreferences: ShortcutPreferences?
    private let perform: (DisplayShortcut) -> Void
    private let report: ([String]) -> Void
    private let intercept: (ShortcutBinding) -> Bool

    init(registrar: HotKeyRegistering? = nil, installHandler: Bool = true,
         perform: @escaping (DisplayShortcut) -> Void, report: @escaping ([String]) -> Void,
         intercept: @escaping (ShortcutBinding) -> Bool = { _ in false }) {
        self.registrar = registrar ?? CarbonHotKeyRegistrar()
        self.perform = perform; self.report = report; self.intercept = intercept
        guard installHandler else { handlerAvailable = true; return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x444D494E else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak controller] in controller?.handleEvent(signature: id.signature, id: id.id) }
            return noErr
        }, 1, &eventType, context, &handler)
        handlerAvailable = status == noErr
    }

    /// Atomic is used for user edits. Startup/toggle registers available keys and reports each unavailable one.
    @discardableResult func configure(_ preferences: ShortcutPreferences, enabled: Bool, atomic: Bool = false) -> String? {
        guard handlerAvailable else {
            let errors = ["Keyboard shortcuts could not start. Panel controls remain available."]
            if !atomic { report(errors) }; return errors.joined(separator: "\n")
        }
        var desired: [ShortcutBinding: DisplayShortcut] = [.recovery: .restore]
        for action in DisplayShortcut.allCases where enabled || action == .restore { desired[preferences[action]] = action }
        var staged: [ShortcutBinding: Registration] = [:]
        var errors: [String] = []
        var editErrors: [String] = []
        let changedBindings = Set(DisplayShortcut.allCases.filter { currentPreferences?[$0] != preferences[$0] }.map { preferences[$0] })
        for binding in desired.keys.sorted(by: { ($0.keyCode, $0.modifiers.rawValue) < ($1.keyCode, $1.modifiers.rawValue) }) {
            let action = desired[binding]!
            if let existing = registrations[binding] {
                staged[binding] = Registration(id: existing.id, action: action)
            } else {
                let id = nextID; nextID += 1
                let status = registrar.register(binding, id: id)
                if status == noErr { staged[binding] = Registration(id: id, action: action) }
                else {
                    let error = "\(action.title) (\(binding.label)) could not register, possibly because another app uses it. Error \(status)."
                    errors.append(error)
                    if changedBindings.contains(binding) { editErrors.append(error) }
                }
            }
        }
        if atomic && !editErrors.isEmpty {
            for (binding, registration) in staged where registrations[binding] == nil { registrar.unregister(id: registration.id) }
            return editErrors.joined(separator: "\n")
        }
        for (binding, registration) in registrations where staged[binding] == nil { registrar.unregister(id: registration.id) }
        registrations = staged; currentPreferences = preferences
        report(errors)
        return nil
    }

    func handleEvent(signature: OSType, id: UInt32) {
        guard signature == Self.signature, let entry = registrations.first(where: { $0.value.id == id }) else { return }
        guard !intercept(entry.key) else { return }
        perform(entry.value.action)
    }

    func shutdown() {
        for registration in registrations.values { registrar.unregister(id: registration.id) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil; handlerAvailable = false
    }
}
