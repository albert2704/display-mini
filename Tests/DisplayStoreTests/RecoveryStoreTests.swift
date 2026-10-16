import AppKit

enum RecoveryStoreTests {
    private static let uuid = "00000000-0000-4000-8000-00000000D001"

    @MainActor static func run() async {
        // The production store uses standard defaults for recovery. Preserve
        // these keys and shut every fixture down before restoring the snapshot.
        let keys = ["ownedDisconnects", "recoveryTrace", "recoveryHeartbeat"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        missingPanelWakeAndOwnership()
        rejectsOtherFailuresAndUnavailableCapture()
        await rejectsStaleWakeCompletion()
        await sleepDuringConnectionDoesNotLeaveBusyState()
        print("Passed recovery store scenarios (wake routing, single flight, ownership, stale completion and sleep during connection).")
    }

    @MainActor private static func fixture() -> DisplayStore {
        UserDefaults.standard.set([uuid], forKey: "ownedDisconnects")
        let store = DisplayStore(startMonitoring: false)
        let panel = DisplayDevice(id: uuid, displayID: 0, name: "Synthetic built-in", builtIn: true)
        panel.connected = false
        store.displays = [panel]
        store.native.connectionHandler = { _, _ in throw DisplayFailure.notAttached }
        store.native.wakeAllowed = true
        return store
    }

    private static var ownsPanel: Bool {
        (UserDefaults.standard.stringArray(forKey: "ownedDisconnects") ?? []).contains(uuid)
    }

    @MainActor private static func stop(_ store: DisplayStore) {
        store.native.connectionHandler = { _, _ in throw DisplayFailure.notAttached }
        store.shutdown()
    }

    @MainActor private static func missingPanelWakeAndOwnership() {
        let store = fixture()
        defer { stop(store) }
        store.refresh()
        precondition(store.native.connectionCalls.count == 1)
        precondition(store.native.connectionCalls[0].uuid == uuid && store.native.connectionCalls[0].enabled)
        precondition(store.native.wakeRequests.count == 1 && store.controlsBusy && ownsPanel)
        store.refresh()
        store.restoreDisplays()
        store.toggleConnection(store.displays[0], enabled: false)
        precondition(store.native.connectionCalls.count == 1 && store.native.wakeRequests.count == 1,
                     "No second transaction may overlap the helper")

        store.native.wakeRequests[0].finish("accepted")
        precondition(store.native.connectionCalls.count == 1,
                     "A wake completion must not directly enable a cached display")
        precondition(!store.controlsBusy && ownsPanel)
        store.native.connectionHandler = nil
        store.restoreDisplays()
        precondition(store.native.connectionCalls.count == 2 && ownsPanel,
                     "An accepted layout transaction must retain ownership until active confirmation")
        precondition(store.native.forgottenWakeTargets.isEmpty)
    }

    @MainActor private static func rejectsOtherFailuresAndUnavailableCapture() {
        let rejected = fixture()
        rejected.native.connectionHandler = { _, _ in throw DisplayFailure.message("Synthetic transaction rejection") }
        rejected.refresh()
        precondition(rejected.native.connectionCalls.count == 1 && rejected.native.wakeChecks == 0)
        precondition(!rejected.controlsBusy && rejected.message != nil && ownsPanel)
        stop(rejected)

        let unavailable = fixture()
        unavailable.native.wakeAllowed = false
        unavailable.refresh()
        precondition(unavailable.native.wakeChecks == 1 && unavailable.native.wakeRequests.isEmpty)
        precondition(!unavailable.controlsBusy && unavailable.message != nil && ownsPanel)
        stop(unavailable)
    }

    @MainActor private static func rejectsStaleWakeCompletion() async {
        for reason in ["shutdown", "ownership", "closed lid", "unknown lid"] {
            let store = fixture()
            store.refresh()
            precondition(store.native.wakeRequests.count == 1)
            switch reason {
            case "shutdown": store.shutdown()
            case "ownership": UserDefaults.standard.set([], forKey: "ownedDisconnects")
            case "closed lid": store.native.lidClosed = true
            default: store.native.lidClosed = nil
            }
            let transactions = store.native.connectionCalls.count
            let reads = store.native.displayListReads
            store.native.wakeRequests[0].finish("accepted")
            precondition(!store.controlsBusy && store.native.connectionCalls.count == transactions)
            // A completion must not queue the normal 0.6-second refresh after
            // its authority is gone. This finishes before the 2-second timer.
            try! await Task.sleep(nanoseconds: 700_000_000)
            precondition(store.native.displayListReads == reads && store.native.connectionCalls.count == transactions)
            stop(store)
        }
    }

    @MainActor private static func sleepDuringConnectionDoesNotLeaveBusyState() async {
        UserDefaults.standard.set([], forKey: "ownedDisconnects")
        let suite = "DisplayMini.RecoveryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplayStore(startMonitoring: true, shortcutDefaults: defaults,
            personalizationDefaults: defaults, advancedDefaults: defaults, presetDefaults: defaults)
        defer { stop(store) }
        let panel = DisplayDevice(id: uuid, displayID: 0, name: "Synthetic built-in", builtIn: true)
        let external = DisplayDevice(id: "00000000-0000-4000-8000-00000000D002", displayID: 0,
                                     name: "Synthetic external", builtIn: false)
        panel.connected = true; external.connected = true
        store.displays = [panel, external]
        store.toggleConnection(panel, enabled: false)
        precondition(store.controlsBusy)
        // These are local observer notifications, not requests to sleep macOS.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try! await Task.sleep(nanoseconds: 900_000_000)
        precondition(!store.controlsBusy, "Invalidating the pending toggle callback must release its busy state")
    }
}
