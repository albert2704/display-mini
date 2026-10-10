import Foundation
import DisplayCore

@MainActor enum PersonalizationStoreTests {
    static func run() {
        let domain = "dev.albert.DisplayMini.personalization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = DisplayStore(startMonitoring: false, personalizationDefaults: defaults)
        let device = DisplayDevice(id: "00000000-0000-4000-8000-00000000D001", displayID: 0, name: "Original screen", builtIn: false)
        store.displays = [device]
        precondition(store.renameDisplay(device, name: "  Desk  "))
        precondition(device.name == "Desk" && device.systemName == "Original screen")
        precondition(store.displayName(for: device.id, fallback: "Preset name") == "Desk")
        let data = defaults.data(forKey: "displayPersonalization")!
        precondition(!store.renameDisplay(device, name: String(repeating: "x", count: 41)))
        precondition(defaults.data(forKey: "displayPersonalization") == data && device.name == "Desk")
        let restored = DisplayStore(startMonitoring: false, personalizationDefaults: defaults)
        precondition(restored.displayName(for: device.id, fallback: "Disconnected screen") == "Desk")
        precondition(store.renameDisplay(device, name: ""))
        precondition(device.name == "Original screen")
        let unidentified = DisplayDevice(id: "display-999", displayID: 0, name: "Unknown", builtIn: false)
        precondition(!store.renameDisplay(unidentified, name: "Cannot route by display ID"))
        precondition(store.personalizationMessage?.contains("no stable identity") == true)

        let mode = FavoriteResolution(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refresh: 60)!
        precondition(!store.setFavorite(device, mode: mode, enabled: true), "Cannot star a stale or invented mode")
        var preferences = DisplayPersonalization()
        try! preferences.setFavorite(uuid: device.id, mode: mode, enabled: true)
        defaults.set(try! JSONEncoder().encode(preferences), forKey: "displayPersonalization")
        let favorites = DisplayStore(startMonitoring: false, personalizationDefaults: defaults)
        favorites.displays = [device]
        let recoveryBefore = UserDefaults.standard.object(forKey: "resolutionRecovery") as? NSDictionary
        favorites.applyFavorite(device, favorite: mode)
        precondition(favorites.message?.contains("not currently available") == true)
        precondition(favorites.pendingResolutionName == nil && favorites.ddc.writes.isEmpty)
        precondition((UserDefaults.standard.object(forKey: "resolutionRecovery") as? NSDictionary) == recoveryBefore)
        device.connected = false
        precondition(favorites.favoriteModes(device).isEmpty)
        precondition(favorites.setFavorite(device, mode: mode, enabled: false), "Unavailable favorites can be removed")

        let corrupt = Data("unreadable".utf8)
        defaults.set(corrupt, forKey: "displayPersonalization")
        defaults.set("untouched", forKey: "otherPreference")
        let broken = DisplayStore(startMonitoring: false, personalizationDefaults: defaults)
        broken.displays = [device]
        precondition(broken.personalizationStorageError != nil)
        precondition(!broken.renameDisplay(device, name: "Must not overwrite"))
        precondition(defaults.data(forKey: "displayPersonalization") == corrupt)
        broken.resetUnreadablePersonalization()
        precondition(defaults.data(forKey: "displayPersonalizationBackup") == corrupt)
        precondition(defaults.data(forKey: "displayPersonalization") == nil)
        precondition(defaults.string(forKey: "otherPreference") == "untouched")
        precondition(broken.renameDisplay(device, name: "Working again"))
        print("Passed 3 personalization store scenarios (name persistence, stale favorites, corruption recovery).")
    }
}
