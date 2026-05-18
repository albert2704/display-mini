import Foundation
import Carbon
import AppKit

@MainActor private final class FakeHotKeys: HotKeyRegistering {
    var active: [UInt32: ShortcutBinding] = [:]
    var unavailable = Set<ShortcutBinding>()
    func register(_ binding: ShortcutBinding, id: UInt32) -> OSStatus {
        if unavailable.contains(binding) || active.values.contains(binding) { return OSStatus(eventHotKeyExistsErr) }
        active[id] = binding; return noErr
    }
    func unregister(id: UInt32) { active.removeValue(forKey: id) }
    func id(for binding: ShortcutBinding) -> UInt32 { active.first { $0.value == binding }!.key }
}

@MainActor enum ShortcutTests {
    static let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .shift])
    static func run() {
        preferenceValidation()
        failedEditPreservesOldKeys()
        resetReusesChordsAndDisableKeepsRecovery()
        existingConflictDoesNotBlockOtherEdits()
        persistenceAndFailedSave()
        recordingCapturesPhysicalKeysAndModifiers()
        recordingRejectsInvalidKeysAndCancels()
        recordingStaysInsideTheEditor()
        recordingInterceptsRegisteredHotKeys()
        print("Passed 9 shortcut scenarios (validation, atomic edits, reset/recovery/event dispatch, independent conflicts, persistence, recording, invalid input/cancel, recording scope, registered-key capture).")
    }
    static func preferenceValidation() {
        var prefs = ShortcutPreferences()
        try! prefs.set(.brightnessUp, binding: custom)
        precondition(try! ShortcutPreferences.decode(JSONEncoder().encode(prefs)) == prefs)
        precondition((try? prefs.set(.brightnessDown, binding: custom)) == nil)
        precondition((try? prefs.set(.mute, binding: .recovery)) == nil)
        for binding in [ShortcutBinding(keyCode: 9999, modifiers: .command),
                        ShortcutBinding(keyCode: 0, modifiers: [.option, .shift]),
                        ShortcutBinding(keyCode: 0, modifiers: .init(rawValue: 256))] {
            precondition((try? prefs.set(.mute, binding: binding)) == nil)
        }
        precondition((try? ShortcutPreferences.decode(Data("bad".utf8))) == nil)
        let data = try! JSONEncoder().encode(prefs)
        var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["schema"] = 99
        precondition((try? ShortcutPreferences.decode(JSONSerialization.data(withJSONObject: json))) == nil)
    }
    static func failedEditPreservesOldKeys() {
        let backend = FakeHotKeys()
        var actions: [DisplayShortcut] = []
        let controller = ShortcutController(registrar: backend, installHandler: false, perform: { actions.append($0) }, report: { _ in })
        let defaults = ShortcutPreferences()
        precondition(controller.configure(defaults, enabled: true) == nil)
        let old = backend.active
        var edited = defaults
        try! edited.set(.brightnessUp, binding: custom)
        // Stage one successful new registration as well, to check cleanup on a later failure.
        try! edited.set(.mute, binding: .init(keyCode: UInt32(kVK_ANSI_A), modifiers: .command))
        backend.unavailable.insert(custom)
        precondition(controller.configure(edited, enabled: true, atomic: true) != nil)
        precondition(backend.active == old)
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: defaults[.brightnessUp]))
        precondition(actions == [.brightnessUp])
        controller.shutdown(); precondition(backend.active.isEmpty)
    }
    static func resetReusesChordsAndDisableKeepsRecovery() {
        let backend = FakeHotKeys()
        var actions: [DisplayShortcut] = []
        let controller = ShortcutController(registrar: backend, installHandler: false, perform: { actions.append($0) }, report: { _ in })
        var edited = ShortcutPreferences()
        try! edited.set(.brightnessUp, binding: custom)
        try! edited.set(.brightnessDown, binding: DisplayShortcut.brightnessUp.defaultBinding)
        try! edited.set(.restore, binding: .init(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .shift]))
        precondition(controller.configure(edited, enabled: true) == nil)
        let obsoleteID = backend.id(for: custom)
        precondition(controller.configure(ShortcutPreferences(), enabled: true, atomic: true) == nil)
        precondition(backend.active.count == 9)
        controller.handleEvent(signature: ShortcutController.signature, id: obsoleteID)
        controller.handleEvent(signature: 0, id: backend.id(for: .recovery))
        precondition(actions.isEmpty)
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: DisplayShortcut.brightnessUp.defaultBinding))
        precondition(actions == [.brightnessUp])
        precondition(controller.configure(edited, enabled: false) == nil)
        precondition(backend.active.count == 2)
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: edited[.restore]))
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: .recovery))
        precondition(actions == [.brightnessUp, .restore, .restore])
        controller.shutdown(); precondition(backend.active.isEmpty)
    }
    static func existingConflictDoesNotBlockOtherEdits() {
        let backend = FakeHotKeys()
        backend.unavailable.insert(DisplayShortcut.mute.defaultBinding)
        var reported: [String] = []
        let controller = ShortcutController(registrar: backend, installHandler: false, perform: { _ in }, report: { reported = $0 })
        var prefs = ShortcutPreferences()
        controller.configure(prefs, enabled: true)
        precondition(reported.count == 1 && backend.active.count == 8)
        try! prefs.set(.brightnessUp, binding: custom)
        precondition(controller.configure(prefs, enabled: true, atomic: true) == nil)
        precondition(backend.active.values.contains(custom) && reported.count == 1)
        controller.shutdown()
    }
    static func persistenceAndFailedSave() {
        let domain = "dev.albert.DisplayMini.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = DisplayStore(startMonitoring: false, shortcutDefaults: defaults)
        store.updateShortcutRegistration = { _ in "Simulated conflict" }
        precondition(!store.saveShortcut(.brightnessUp, binding: custom))
        precondition(defaults.data(forKey: "shortcutBindings") == nil)
        precondition(store.shortcutPreferences[.brightnessUp] == DisplayShortcut.brightnessUp.defaultBinding)
        store.updateShortcutRegistration = { _ in nil }
        precondition(store.saveShortcut(.brightnessUp, binding: custom))
        let relaunched = DisplayStore(startMonitoring: false, shortcutDefaults: defaults)
        precondition(relaunched.shortcutPreferences[.brightnessUp] == custom)
        relaunched.updateShortcutRegistration = { _ in nil }
        precondition(relaunched.resetShortcuts())
        precondition(try! ShortcutPreferences.decode(defaults.data(forKey: "shortcutBindings")!) == ShortcutPreferences())
        let bad = Data("corrupt".utf8)
        defaults.set(bad, forKey: "shortcutBindings")
        let recovered = DisplayStore(startMonitoring: false, shortcutDefaults: defaults)
        precondition(recovered.shortcutStorageMessage != nil && defaults.data(forKey: "shortcutBindings") == bad)
        recovered.updateShortcutRegistration = { _ in nil }
        precondition(recovered.resetShortcuts())
        precondition(defaults.data(forKey: "shortcutBindingsBackup") == bad)
    }

    static func event(_ code: Int, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown,
                      repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: repeating, keyCode: UInt16(code))!
    }

    static func recordingCapturesPhysicalKeysAndModifiers() {
        let recorder = ShortcutRecorder(isForeground: { true })
        var captured: [ShortcutBinding] = []
        recorder.beginEditing()
        recorder.start(installMonitor: false) { captured.append($0) }
        precondition(recorder.handle(event(kVK_Control, flags: [.control, .shift], type: .flagsChanged)))
        precondition(recorder.heldModifiers == "⌃⇧" && captured.isEmpty)
        precondition(recorder.handle(event(kVK_ANSI_K, flags: [.control, .shift, .capsLock, .function, .numericPad])))
        precondition(captured == [custom] && !recorder.isRecording)
        // Subsequent typing cannot replace the captured draft without another explicit start.
        precondition(!recorder.handle(event(kVK_ANSI_A, flags: .command)))
        recorder.start(installMonitor: false) { captured.append($0) }
        precondition(recorder.handle(event(kVK_F2, flags: [.command, .option, .function])))
        precondition(captured.last == .init(keyCode: UInt32(kVK_F2), modifiers: [.command, .option]))
        recorder.endEditing()
    }

    static func recordingRejectsInvalidKeysAndCancels() {
        let recorder = ShortcutRecorder(isForeground: { true })
        var captured: [ShortcutBinding] = []
        recorder.beginEditing()
        recorder.start(installMonitor: false) { captured.append($0) }
        for invalid in [event(kVK_ANSI_K), event(kVK_ANSI_K, flags: [.option, .shift]),
                        event(kVK_Tab, flags: .command), event(kVK_ANSI_K, flags: .command, repeating: true)] {
            precondition(recorder.handle(invalid))
            precondition(recorder.isRecording && captured.isEmpty)
        }
        precondition(recorder.message != nil)
        precondition(recorder.handle(event(kVK_Escape)))
        precondition(!recorder.isRecording && captured.isEmpty)
        // Cancel and end may be called repeatedly as nested popovers disappear.
        recorder.cancel(); recorder.endEditing(); recorder.endEditing()
        precondition(!recorder.isEditing && !recorder.isRecording)
    }

    static func recordingStaysInsideTheEditor() {
        var foreground = true
        let recorder = ShortcutRecorder(isForeground: { foreground })
        var captured: [ShortcutBinding] = []
        recorder.start(installMonitor: false) { captured.append($0) }
        precondition(!recorder.isRecording)
        recorder.beginEditing()
        recorder.start(installMonitor: false) { captured.append($0) }
        foreground = false
        precondition(!recorder.handle(event(kVK_ANSI_K, flags: .command)))
        precondition(!recorder.isRecording && captured.isEmpty && !recorder.intercept(custom))
        recorder.start(installMonitor: false) { captured.append($0) }
        precondition(!recorder.isRecording)
        foreground = true
        recorder.start(installMonitor: false) { captured.append($0) }
        recorder.endEditing()
        precondition(!recorder.handle(event(kVK_ANSI_K, flags: .command)) && captured.isEmpty)
    }

    static func recordingInterceptsRegisteredHotKeys() {
        var foreground = true
        let recorder = ShortcutRecorder(isForeground: { foreground })
        let backend = FakeHotKeys()
        var actions: [DisplayShortcut] = []
        var captured: [ShortcutBinding] = []
        let controller = ShortcutController(registrar: backend, installHandler: false,
            perform: { actions.append($0) }, report: { _ in }, intercept: { recorder.intercept($0) })
        controller.configure(ShortcutPreferences(), enabled: true)
        let registrations = backend.active
        let brightness = DisplayShortcut.brightnessUp.defaultBinding
        recorder.beginEditing()
        recorder.start(installMonitor: false) { captured.append($0) }
        controller.handleEvent(signature: 0, id: backend.id(for: brightness))
        precondition(captured.isEmpty)
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: brightness))
        precondition(captured == [brightness] && actions.isEmpty && !recorder.isRecording)
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: brightness))
        precondition(actions.isEmpty) // Held keys do not change the monitor after capture.
        recorder.start(installMonitor: false) { captured.append($0) }
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: .recovery))
        precondition(captured.last == .recovery && actions.isEmpty)
        foreground = false
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: .recovery))
        precondition(actions == [.restore]) // Global recovery remains available outside the focused editor.
        foreground = true; recorder.endEditing()
        controller.handleEvent(signature: ShortcutController.signature, id: backend.id(for: brightness))
        precondition(actions == [.restore, .brightnessUp] && backend.active == registrations)
        controller.shutdown()
    }
}
