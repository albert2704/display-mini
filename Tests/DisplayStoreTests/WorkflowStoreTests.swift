import AppKit
import DisplayCore

enum WorkflowStoreTests {
    @MainActor static func run() async {
        let suite = "DisplayMini.WorkflowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        await selectedParticipants(defaults)
        defaults.removePersistentDomain(forName: suite)
        await corruptSelection(defaults)
        defaults.removePersistentDomain(forName: suite)
        await busyTargets(defaults)
        defaults.removePersistentDomain(forName: suite)
        automationGuards(defaults)
        defaults.removePersistentDomain(forName: suite)
        await scheduledExecution(defaults)
        print("Passed 5 workflow store scenarios (selected participants, corrupt selection, busy linked targets, automation recovery guards, scheduled hardware outcomes).")
    }

    @MainActor static func selectedParticipants(_ defaults: UserDefaults) async {
        let (store, first) = AdvancedStoreTests.fixture(defaults)
        let second = monitor("00000000-0000-4000-8000-00000000B002")
        let excluded = monitor("00000000-0000-4000-8000-00000000B003")
        store.displays += [second, excluded]
        store.linkedBrightnessEnabled = true
        store.setBrightnessLinkMode(.selected)
        store.setBrightnessLinkMember(first.id, included: true)
        store.setBrightnessLinkMember(second.id, included: true)
        precondition(store.ddc.writes.isEmpty && first.pendingBrightness == nil)
        let reloaded = DisplayStore(startMonitoring: false, advancedDefaults: defaults)
        precondition(reloaded.brightnessLinkSelection == store.brightnessLinkSelection)
        store.setBrightness(first, 0.65)
        await StoreTests.debounce()
        precondition(Set(store.ddc.writes.map(\.uuid)) == [first.id, second.id])
        for write in store.ddc.writes { write.finish(.success(())) }
        store.setBrightness(excluded, 0.4)
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 3 && store.ddc.writes.last?.uuid == excluded.id)
        store.ddc.writes.last?.finish(.success(()))
        store.setBrightnessLinkMember(first.id, included: false)
        store.setBrightnessLinkMember(second.id, included: false)
        store.setBrightness(first, 0.55)
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 4 && store.ddc.writes.last?.uuid == first.id)
        store.ddc.writes.last?.finish(.success(()))
        store.setBrightnessLinkMember(second.id, included: true)
        store.displays.removeAll { $0 === second }
        precondition(store.brightnessLinkSelection.includes(second.id), "Unplug does not forget selection")
        store.shutdown()
    }

    @MainActor static func corruptSelection(_ defaults: UserDefaults) async {
        let bad = Data("{bad".utf8)
        defaults.set(bad, forKey: "brightnessLinkSelection")
        let (store, first) = AdvancedStoreTests.fixture(defaults)
        let other = monitor(UUID().uuidString)
        store.displays.append(other)
        store.linkedBrightnessEnabled = true
        precondition(store.brightnessLinkStorageError != nil)
        store.setBrightnessLinkMode(.all)
        precondition(defaults.data(forKey: "brightnessLinkSelection") == bad)
        store.setBrightness(first, 0.6)
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 1 && other.pendingBrightness == nil)
        store.ddc.writes[0].finish(.success(()))
        store.resetUnreadableBrightnessSelection()
        precondition(defaults.data(forKey: "brightnessLinkSelectionBackup") == bad)
        precondition(store.brightnessLinkStorageError == nil && store.brightnessLinkSelection.mode == .selected)
        precondition(store.brightnessLinkSelection.displayUUIDs.isEmpty)
        store.shutdown()
        defaults.set("wrong storage type", forKey: "brightnessLinkSelection")
        let badType = DisplayStore(startMonitoring: false, advancedDefaults: defaults)
        precondition(badType.brightnessLinkStorageError != nil && !badType.brightnessLinkSelection.includes(first.id))
        badType.resetUnreadableBrightnessSelection()
        precondition(defaults.data(forKey: "brightnessLinkSelectionBackup") == bad, "Reset must preserve previous backups")
    }

    @MainActor static func busyTargets(_ defaults: UserDefaults) async {
        let (store, first) = AdvancedStoreTests.fixture(defaults)
        let writing = monitor(UUID().uuidString)
        writing.writesInFlight = 1
        let volume = monitor(UUID().uuidString)
        volume.pendingVolume = DispatchWorkItem {}
        store.displays += [writing, volume]
        store.linkedBrightnessEnabled = true
        store.setBrightness(first, 0.6)
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 1)
        precondition(store.message?.contains("skipped 2") == true)
        store.ddc.writes[0].finish(.success(()))
        store.shutdown()
    }

    @MainActor static func automationGuards(_ defaults: UserDefaults) {
        let (store, first) = AdvancedStoreTests.fixture(defaults)
        let preset = DisplayPreset(name: "Scheduled", displays: [.init(uuid: first.id, name: first.name, brightness: 0.6, volume: nil)])
        precondition(store.automationSkipReason(for: preset) == nil)
        store.unresolvedRecovery = true
        precondition(store.automationSkipReason(for: preset)?.contains("recovery") == true)
        store.unresolvedRecovery = false
        store.connectionBusy = true
        precondition(store.automationSkipReason(for: preset) != nil)
        store.connectionBusy = false
        let missing = DisplayPreset(name: "Missing", displays: [.init(uuid: UUID().uuidString, name: "Offline", brightness: 0.6, volume: nil)])
        precondition(store.automationSkipReason(for: missing)?.contains("connected") == true)
        store.shutdown()
        precondition(store.automationSkipReason(for: preset) != nil)
    }

    @MainActor private static func monitor(_ uuid: String) -> DisplayDevice {
        let device = DisplayDevice(id: uuid, displayID: 0, name: "Test participant", builtIn: false)
        device.ddcBrightness = true; device.forceSoftware = false
        return device
    }

    @MainActor static func scheduledExecution(_ defaults: UserDefaults) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 8, minute: 59, second: 59))!
        let automation = PresetAutomationController(defaults: defaults, clock: { now }, calendar: { calendar }, automaticTimers: false)
        let store = DisplayStore(startMonitoring: false, advancedDefaults: defaults, presetDefaults: defaults, automationController: automation)
        let device = monitor(UUID().uuidString)
        store.displays = [device]
        precondition(store.savePreset(name: "Scheduled test"))
        let preset = store.presetLibrary.presets[0]
        store.startAutomations()
        for minute in 0...3 {
            precondition(automation.save(presetID: preset.id, hour: 9, minute: minute, recurrence: .daily))
            precondition(automation.setEnabled(automation.library.schedules.last!.id, enabled: true))
        }
        let rules = automation.library.schedules.map(\.id)
        now += 2
        automation.evaluate()
        precondition(automation.statuses[rules[0]]?.hasPrefix("Started") == true)
        await StoreTests.debounce()
        store.ddc.writes[0].finish(.success(()))
        precondition(automation.statuses[rules[0]]?.hasPrefix("Applied") == true)

        now += 60
        automation.evaluate()
        await StoreTests.debounce()
        store.ddc.writes[1].finish(.failure(.rejected))
        precondition(automation.statuses[rules[1]]?.hasPrefix("Failed") == true)

        now += 60
        automation.evaluate()
        await StoreTests.debounce()
        store.restoreDisplays()
        precondition(automation.statuses[rules[2]]?.contains("interrupted") == true)
        store.ddc.writes[2].finish(.success(()))
        // Reconcile the late write using the fake hardware, before the next schedule.
        precondition(!store.ddc.reads.isEmpty)
        store.ddc.reads.last?(.failure(.rejected))
        now += 60
        automation.evaluate()
        precondition(automation.statuses[rules[3]]?.hasPrefix("Started") == true, "Interruption must free the automation for later rules")
        await StoreTests.debounce()
        if let pending = store.ddc.writes.last, store.applyingPresetName != nil { pending.finish(.success(())) }
        precondition(automation.statuses[rules[3]]?.hasPrefix("Applied") == true)
        store.shutdown()
    }
}
