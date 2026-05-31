import AppKit
import DisplayCore

enum AdvancedStoreTests {
    static let uuid = "00000000-0000-4000-8000-00000000A001"
    @MainActor static func fixture(_ defaults: UserDefaults) -> (DisplayStore, DisplayDevice) {
        let store = DisplayStore(startMonitoring: false, advancedDefaults: defaults)
        let device = DisplayDevice(id: uuid, displayID: 0, name: "Test screen", builtIn: false)
        device.forceSoftware = false; device.ddcBrightness = true
        device.brightness = 0.8; device.confirmedBrightness = 0.8
        store.displays = [device]
        return (store, device)
    }
    static func probe(input: Int = 17) -> AdvancedDDCProbe {
        let json: [String: Any] = ["schema": 1, "uuid": uuid, "transport": "standard", "serviceCount": 1, "delayMS": 50,
            "contrast": ["status": "ok", "attempts": 1, "current": 100, "maximum": 200],
            "input": ["status": "ok", "attempts": 1, "current": input, "maximum": 0]]
        return AdvancedDDCProbe.parse(try! JSONSerialization.data(withJSONObject: json), expectedUUID: uuid, timing: .standard)!
    }
    @MainActor static func run() async {
        let suite = "DisplayMini.AdvancedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        detectionAndContrast(defaults)
        inputDeliveryAndRecoveryGuard(defaults)
        staleDetection(defaults)
        await linkedBrightness(defaults)
        await presetIsolation(defaults)
        print("Passed 5 advanced store scenarios (contrast rollback, input delivery and recovery guard, stale detection, linked edits and persistence, preset isolation).")
    }
    @MainActor static func detectionAndContrast(_ defaults: UserDefaults) {
        let (store, device) = fixture(defaults)
        precondition(store.ddc.advancedReads.isEmpty && store.ddc.writes.isEmpty)
        store.setContrast(device, 0.3)
        precondition(store.ddc.writes.isEmpty, "No write without a valid capability read")
        store.detectAdvancedControls(device)
        store.detectAdvancedControls(device)
        store.setBrightness(device, 0.2)
        precondition(device.advancedBusy && !store.canSavePreset && device.pendingBrightness == nil)
        precondition(store.ddc.advancedReads.count == 1 && store.ddc.reads.isEmpty)
        store.ddc.advancedReads[0](.success(probe()))
        precondition(device.contrast == 0.5 && !device.advancedBusy)
        store.setContrast(device, .nan)
        store.setContrast(device, 0.5)
        precondition(store.ddc.writes.isEmpty)
        store.setContrast(device, 0.4)
        precondition(store.ddc.writes[0].attribute == "contrast" && store.ddc.writes[0].value == 80)
        store.ddc.writes[0].finish(.success(()))
        precondition(device.contrast == 0.4 && !device.writing)
        store.setContrast(device, 0.1)
        store.ddc.writes[1].finish(.failure(.rejected))
        precondition(device.contrast == 0.4 && device.advancedMessage != nil && !device.advancedBusy)
        device.connected = false
        store.setContrast(device, 0.9)
        precondition(store.ddc.writes.count == 2)
    }
    @MainActor static func inputDeliveryAndRecoveryGuard(_ defaults: UserDefaults) {
        let (store, device) = fixture(defaults)
        device.advancedProbe = probe(input: 0)
        store.switchInput(device, to: .hdmi1)
        precondition(store.ddc.inputs.isEmpty, "An unidentified input cannot enable switching")
        device.advancedProbe = probe(); device.contrast = 0.5
        store.switchInput(device, to: .hdmi1)
        precondition(store.ddc.inputs.isEmpty)
        let builtin = DisplayDevice(id: UUID().uuidString, displayID: 1, name: "Built in", builtIn: true)
        builtin.connected = false; store.displays.append(builtin)
        let original = UserDefaults.standard.object(forKey: "ownedDisconnects")
        defer { UserDefaults.standard.set(original, forKey: "ownedDisconnects") }
        UserDefaults.standard.set([builtin.id], forKey: "ownedDisconnects")
        store.switchInput(device, to: .displayPort1)
        precondition(store.ddc.inputs.isEmpty && device.advancedMessage?.contains("Restore") == true)
        builtin.connected = true
        store.switchInput(device, to: .displayPort1)
        precondition(store.ddc.inputs.count == 1 && store.ddc.inputs[0].value == 15)
        precondition(store.ddc.writes.isEmpty, "Input uses command delivery, not verified continuous writes")
        store.ddc.inputs[0].finish(.success(()))
        precondition(device.advancedProbe == nil && device.advancedMessage?.contains("cannot be confirmed") == true)
        store.switchInput(device, to: .hdmi2)
        precondition(store.ddc.inputs.count == 1, "Must detect again after switching")
        device.advancedProbe = probe()
        store.switchInput(device, to: .hdmi2)
        store.ddc.inputs[1].finish(.failure(.rejected))
        precondition(device.advancedMessage?.contains("may still have changed") == true)
    }
    @MainActor static func staleDetection(_ defaults: UserDefaults) {
        let (store, device) = fixture(defaults)
        store.detectAdvancedControls(device)
        store.refresh() // Fake native discovery removes the target.
        store.ddc.advancedReads[0](.success(probe()))
        precondition(device.advancedProbe == nil && !device.advancedBusy && store.displays.isEmpty)
        store.setContrast(device, 0.7)
        precondition(store.ddc.writes.isEmpty)
        let (next, other) = fixture(defaults)
        other.advancedProbe = probe(); other.contrast = 0.5
        next.setContrast(other, 0.8)
        next.shutdown()
        next.ddc.writes[0].finish(.success(()))
        precondition(other.contrast == nil && other.advancedProbe == nil && !other.writing)
    }
    @MainActor static func linkedBrightness(_ defaults: UserDefaults) async {
        let (store, device) = fixture(defaults)
        precondition(!store.linkedBrightnessEnabled)
        let other = DisplayDevice(id: UUID().uuidString, displayID: 2, name: "Other", builtIn: false)
        other.ddcBrightness = true; other.forceSoftware = false
        let busy = DisplayDevice(id: UUID().uuidString, displayID: 3, name: "Busy", builtIn: false)
        busy.reading = true
        store.displays += [other, busy]
        store.linkedBrightnessEnabled = true
        precondition(store.ddc.writes.isEmpty && device.pendingBrightness == nil)
        precondition(DisplayStore(startMonitoring: false, advancedDefaults: defaults).linkedBrightnessEnabled)
        store.setBrightness(device, 0.6)
        store.setBrightness(device, 0.7) // Latest edit must win before the debounce.
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 2 && Set(store.ddc.writes.map(\.uuid)) == [device.id, other.id])
        precondition(store.ddc.writes.allSatisfy { $0.attribute == "luminance" && $0.value == 62 })
        precondition(busy.pendingBrightness == nil && store.message?.contains("skipped 1") == true)
        for write in store.ddc.writes { write.finish(.success(())) }
        precondition(device.confirmedBrightness == 0.7 && other.confirmedBrightness == 0.7)
        store.linkedBrightnessEnabled = false
        precondition(!DisplayStore(startMonitoring: false, advancedDefaults: defaults).linkedBrightnessEnabled)
    }
    @MainActor static func presetIsolation(_ defaults: UserDefaults) async {
        let (store, device) = fixture(defaults)
        let other = DisplayDevice(id: UUID().uuidString, displayID: 2, name: "Other", builtIn: false)
        other.ddcBrightness = true; store.displays.append(other)
        store.linkedBrightnessEnabled = true
        let preset = DisplayPreset(name: "One screen", displays: [.init(uuid: device.id, name: device.name, brightness: 0.6, volume: nil)])
        precondition(store.applyPreset(preset))
        store.detectAdvancedControls(device)
        precondition(store.ddc.advancedReads.isEmpty)
        await StoreTests.debounce()
        precondition(store.ddc.writes.count == 1 && store.ddc.writes[0].uuid == device.id)
        store.ddc.writes[0].finish(.success(()))
        precondition(other.brightness == 1)
        store.linkedBrightnessEnabled = false
    }
}
