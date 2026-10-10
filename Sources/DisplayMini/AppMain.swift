import AppKit
import Combine
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: DisplayStore!
    private var shortcuts: ShortcutController?
    private var shortcutSetting: AnyCancellable?

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
        shortcuts = ShortcutController(perform: { [weak self] action in
            guard let self else { return }
            if action == .restore { self.store.restoreDisplays(); self.showPanel(refresh: false) }
            else if !self.store.performShortcut(action) { self.showPanel(refresh: false) }
        }, report: { [weak self] errors in
            self?.store.shortcutErrors = errors
        }, intercept: { [weak self] binding in
            self?.store.shortcutRecorder.intercept(binding) ?? false
        })
        shortcuts?.configure(store.shortcutPreferences, enabled: store.shortcutsEnabled)
        store.updateShortcutRegistration = { [weak self] preferences in
            guard let self, let shortcuts = self.shortcuts else { return "Keyboard shortcuts are not ready yet." }
            return shortcuts.configure(preferences, enabled: self.store.shortcutsEnabled, atomic: true)
        }
        shortcutSetting = store.$shortcutsEnabled.dropFirst().sink { [weak self] enabled in
            guard let self else { return }
            self.shortcuts?.configure(self.store.shortcutPreferences, enabled: enabled)
        }
        showPanel()
    }

    @objc private func togglePanel() { popover.isShown ? popover.performClose(nil) : showPanel() }
    private func showPanel(refresh: Bool = true) {
        guard let button = statusItem?.button else { return }
        if refresh && store.applyingPresetName == nil { store.refresh() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }

    func applicationWillTerminate(_ notification: Notification) {
        store?.shortcutRecorder.endEditing()
        store?.shutdown()
        shortcutSetting = nil
        shortcuts?.shutdown()
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
