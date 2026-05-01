import AppKit
import Carbon
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: DisplayStore!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            running.activate(options: [])
            NSApplication.shared.terminate(nil)
            return
        }
        store = DisplayStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display Mini")
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(togglePanel)
            button.toolTip = "Display Mini"
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(store: store))
        popover.animates = false
        registerRecoveryShortcut()
        showPanel()
    }

    @objc private func togglePanel() { popover.isShown ? popover.performClose(nil) : showPanel() }
    private func showPanel() {
        guard let button = statusItem?.button else { return }
        store.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }

    private func registerRecoveryShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.store.restoreDisplays(); delegate.showPanel() }
            return noErr
        }, 1, &eventType, pointer, &eventHandler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x444D494E, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { store.message = "The restore shortcut is in use. Restore Displays is still available in the panel." }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

@main struct DisplayMiniApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
