import AppKit
import Carbon
import Combine

/// Listens only during an explicit recording in the foreground shortcut editor.
@MainActor final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    @Published private(set) var heldModifiers = ""
    private(set) var isEditing = false
    private var accept: ((ShortcutBinding) -> Void)?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let isForeground: @MainActor () -> Bool

    init(isForeground: @escaping @MainActor () -> Bool = { NSApp.isActive }) {
        self.isForeground = isForeground
    }

    func beginEditing() { isEditing = true }

    func endEditing() {
        stop(); isEditing = false; message = nil
    }

    func start(installMonitor: Bool = true, accept: @escaping (ShortcutBinding) -> Void) {
        stop(); message = nil; heldModifiers = ""
        guard isEditing, isForeground() else { return }
        self.accept = accept; isRecording = true
        guard installMonitor else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == true }
            return consumed ? nil : event
        }
        guard monitor != nil else {
            stop(); message = "Recording could not start. You can still choose a key below."; return
        }
        observers = [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
    }

    func cancel() {
        stop(); message = "Recording canceled. Your draft is unchanged."
    }

    /// Always tears down the monitor before invoking a callback or leaving the editor.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        accept = nil; isRecording = false; heldModifiers = ""; message = nil
    }

    @discardableResult func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        guard isForeground() else { cancel(); return false }
        guard event.type == .keyDown || event.type == .flagsChanged else { return false }
        let modifiers = Self.modifiers(event.modifierFlags)
        if event.type == .flagsChanged { heldModifiers = modifiers.label; return true }
        if event.keyCode == UInt16(kVK_Escape) { cancel(); return true }
        guard !event.isARepeat else { return true }
        receive(.init(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        return true
    }

    /// Registered Carbon hotkeys bypass the local NSEvent monitor. Route them here too.
    /// Keep consuming them in the focused editor after capture so a held key cannot run an action.
    func intercept(_ binding: ShortcutBinding) -> Bool {
        guard isEditing, isForeground() else { return false }
        if isRecording { receive(binding) }
        return true
    }

    private func receive(_ binding: ShortcutBinding) {
        guard binding.isValid else {
            message = ShortcutPreferenceError.invalid.localizedDescription
            return
        }
        let accept = accept
        stop()
        message = "Recorded \(binding.label). Click Save to use it."
        accept?(binding)
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
