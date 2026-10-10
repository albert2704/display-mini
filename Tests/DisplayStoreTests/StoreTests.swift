import AppKit
import DisplayCore

// Compile the real store against these hardware substitutes. No physical display writes.
@MainActor final class NativeDisplays {
    var canConnect = true
    var lidClosed: Bool? = false
    var activeExternalLinkCount: Int? = 1
    func displayIDs() -> [CGDirectDisplayID] { [] }
    func uuid(_ id: CGDirectDisplayID) -> String { "unused" }
    func currentID(for uuid: String) -> CGDirectDisplayID? { nil }
    func brightness(_ id: CGDirectDisplayID) -> Double? { nil }
    func setBrightness(_ id: CGDirectDisplayID, value: Double) throws {}
    func setConnected(uuid: String, enabled: Bool) throws {}
    func setMode(_ id: CGDirectDisplayID, mode: CGDisplayMode, permanent: Bool = false) throws {}
}
@MainActor final class DimmingWindows {
    func set(uuid: String, screen: NSScreen?, fraction: Double) {}
    func remove(_ uuid: String) {}
    func removeAll() {}
}
enum DDCFailure: LocalizedError { case rejected; var errorDescription: String? { "Simulated failure" } }
@MainActor final class DDCClient {
    struct Write { let attribute: String; let value: Int; let finish: (Result<Void, DDCFailure>) -> Void }
    var writes: [Write] = []
    var reads: [(Result<DDCProbe, DDCFailure>) -> Void] = []
    func read(uuid: String, timing: DDCTiming, completion: @escaping (Result<DDCProbe, DDCFailure>) -> Void) { reads.append(completion) }
    func write(uuid: String, timing: DDCTiming, attribute: String, value: Int, completion: @escaping (Result<Void, DDCFailure>) -> Void) {
        writes.append(.init(attribute: attribute, value: value, finish: completion))
    }
}

@main struct StoreTests {
    @MainActor static func main() async {
        await sequentialSuccessAndFailure()
        await cancellationReconcilesLateWrite()
        await muteRejectsFailedRestore()
        await slowRecoveryWriteReconciles()
        shortcutGuards()
        ShortcutTests.run()
        PersonalizationStoreTests.run()
        print("Passed 5 store orchestration scenarios (sequential apply, canceled write reconciliation, mute rollback, slow recovery, shortcut guards).")
    }
    static let uuid = "00000000-0000-4000-8000-00000000F001"
    @MainActor static func fixture() -> (DisplayStore, DisplayDevice, DisplayPreset) {
        let store = DisplayStore(startMonitoring: false)
        let device = DisplayDevice(id: uuid, displayID: 0, name: "Synthetic monitor", builtIn: false)
        device.forceSoftware = false; device.ddcBrightness = true
        device.brightness = 0.8; device.confirmedBrightness = 0.8
        device.volume = 0.6; device.confirmedVolume = 0.6
        store.displays = [device]
        return (store, device, .init(name: "Test", displays: [.init(uuid: uuid, name: device.name, brightness: 0.7, volume: 0.3)]))
    }
    @MainActor static func debounce() async { try! await Task.sleep(nanoseconds: 200_000_000) }

    @MainActor static func sequentialSuccessAndFailure() async {
        let (store, device, preset) = fixture()
        precondition(store.applyPreset(preset))
        precondition(!store.canSavePreset)
        store.setVolume(device, 0.9)
        precondition(device.volume == 0.6, "manual writes must be blocked during a preset")
        await debounce()
        precondition(store.ddc.writes.count == 1 && store.ddc.writes[0].attribute == "luminance")
        precondition(device.confirmedBrightness == 0.8)
        store.ddc.writes[0].finish(.success(()))
        await debounce()
        precondition(store.ddc.writes.count == 2 && store.ddc.writes[1].attribute == "volume")
        precondition(store.applyingPresetName != nil, "completion must wait for the last write")
        store.ddc.writes[1].finish(.failure(.rejected))
        precondition(store.applyingPresetName == nil && store.canSavePreset)
        precondition(device.confirmedBrightness == 0.7 && device.volume == 0.6)
        precondition(store.presetMessage?.contains("1 failed") == true)
    }

    @MainActor static func cancellationReconcilesLateWrite() async {
        let (store, device, preset) = fixture()
        precondition(store.applyPreset(preset))
        await debounce()
        // Restore invalidates the batch while its first DDC write is still in flight.
        store.restoreDisplays()
        precondition(store.applyingPresetName == nil && !store.canSavePreset)
        store.setVolume(device, 0.9)
        store.setBrightness(device, 0.9)
        precondition(device.pendingVolume == nil && device.pendingBrightness == nil)
        store.ddc.writes[0].finish(.success(()))
        precondition(store.ddc.reads.count == 1 && device.reading)
        precondition(!store.canSavePreset, "cannot capture old levels before reconciliation")
        let json: [String: Any] = ["schema": 1, "uuid": uuid, "transport": "standard", "serviceCount": 1, "delayMS": 50,
            "brightness": ["status": "ok", "attempts": 1, "current": 63, "maximum": 100],
            "volume": ["status": "ok", "attempts": 1, "current": 60, "maximum": 100]]
        let probe = DDCProbe.parse(try! JSONSerialization.data(withJSONObject: json), expectedUUID: uuid, timing: .standard)!
        store.ddc.reads[0](.success(probe))
        precondition(!device.needsControlRead && store.canSavePreset)
        precondition(abs(device.confirmedBrightness - 0.704) < 0.00001)
        precondition(store.ddc.writes.count == 1, "canceled preset must never start its volume step")
        store.shutdown() // cancels the scheduled recovery refresh before it can enumerate real screens
    }

    @MainActor static func muteRejectsFailedRestore() async {
        let (store, device, _) = fixture()
        device.volumeBeforeMute = 0.6
        store.toggleMute(device)
        await debounce()
        precondition(store.ddc.writes[0].value == 0)
        store.ddc.writes[0].finish(.success(()))
        precondition(device.confirmedVolume == 0 && device.volumeBeforeMute == 0.6)
        store.toggleMute(device)
        await debounce()
        precondition(store.ddc.writes[1].value == 60)
        store.ddc.writes[1].finish(.failure(.rejected))
        precondition(device.volume == 0 && device.volumeBeforeMute == 0.6)
    }

    @MainActor static func slowRecoveryWriteReconciles() async {
        let (store, device, _) = fixture()
        device.brightness = 0.1; device.confirmedBrightness = 0.1
        store.restoreDisplays()
        await debounce()
        precondition(store.ddc.writes.count == 1 && !store.canSavePreset)
        // Even a current, successful recovery write must reconcile its hardware result.
        store.ddc.writes[0].finish(.success(()))
        precondition(store.ddc.reads.count == 1 && device.reading)
        store.ddc.reads[0](.failure(.rejected))
        precondition(!device.needsControlRead && store.canSavePreset)
        precondition(device.volume == nil, "failed re-read must not expose stale monitor volume")
        store.shutdown()
    }

    @MainActor static func shortcutGuards() {
        let (store, device, _) = fixture()
        let original = store.shortcutsEnabled
        defer { store.shortcutsEnabled = original }
        store.shortcutsEnabled = false
        precondition(store.performShortcut(.brightnessUp))
        precondition(device.pendingBrightness == nil)
        store.shortcutsEnabled = true
        store.connectionBusy = true
        precondition(!store.performShortcut(.brightnessUp))
        precondition(device.pendingBrightness == nil)
        store.connectionBusy = false
        precondition(!store.performShortcut(.preset3), "missing preset slot should show feedback")
        precondition(store.message?.contains("Save a preset") == true)
        // Synthetic display ID zero cannot match the pointer's actual screen. Never use another row.
        precondition(!store.performShortcut(.volumeUp))
        precondition(device.pendingVolume == nil && device.volume == 0.6)
    }
}
