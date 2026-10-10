import Foundation
import DisplayCore

enum PersonalizationTests {
    static let uuid = "00000000-0000-4000-8000-00000000A001"
    static let other = "00000000-0000-4000-8000-00000000A002"
    static let mode = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 60)!
    static func run() {
        namesAndDisplayIsolation()
        favoriteIdentityAndOrder()
        corruptionAndBounds()
        limitsAndRemoval()
        print("Passed 4 personalization scenarios (names and identity, mode variants and order, corruption, storage limits).")
    }
    static func namesAndDisplayIsolation() {
        var value = DisplayPersonalization()
        try! value.rename(uuid: uuid.lowercased(), name: "  Desk screen  ")
        precondition(value.entry(for: uuid).name == "Desk screen")
        precondition(value.entry(for: other).name == nil)
        let before = value
        for name in ["bad\nname", "bad\tname", "bad\u{0}name", String(repeating: "a", count: 41)] {
            precondition((try? value.rename(uuid: uuid, name: name)) == nil)
            precondition(value == before)
        }
        precondition((try? value.rename(uuid: "bad-id", name: "Desk")) == nil)
        try! value.setFavorite(uuid: uuid, mode: mode, enabled: true)
        try! value.rename(uuid: uuid, name: "")
        precondition(value.entry(for: uuid).name == nil && value.entry(for: uuid).favorites == [mode])
        precondition(try! DisplayPersonalization.decode(JSONEncoder().encode(value)) == value)
        try! value.setFavorite(uuid: uuid, mode: mode, enabled: false)
        precondition(value.displays.isEmpty)
    }
    static func favoriteIdentityAndOrder() {
        // Native IDs are deliberately not part of this value; rediscovery may assign new IDs.
        let same = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 60.00001)!
        let standard = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 1728, pixelHeight: 1117, refresh: 60)!
        let tallerPixels = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2304, refresh: 60)!
        let fractional = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 59.94)!
        let variable = FavoriteResolution(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 0)!
        precondition(mode == same && Set([mode, standard, tallerPixels, fractional, variable]).count == 5)
        var value = DisplayPersonalization()
        for candidate in [mode, same, standard, fractional] { try! value.setFavorite(uuid: uuid, mode: candidate, enabled: true) }
        precondition(value.entry(for: uuid).favorites == [mode, standard, fractional])
        try! value.setFavorite(uuid: uuid, mode: standard, enabled: false)
        precondition(value.entry(for: uuid).favorites == [mode, fractional])
        precondition(value.entry(for: other).favorites.isEmpty)
        precondition(try! DisplayPersonalization.decode(JSONEncoder().encode(value)) == value)
    }
    static func corruptionAndBounds() {
        for refresh in [Double.nan, .infinity, -1, 2001] {
            precondition(FavoriteResolution(width: 1, height: 1, pixelWidth: 1, pixelHeight: 1, refresh: refresh) == nil)
        }
        precondition(FavoriteResolution(width: 0, height: 1, pixelWidth: 1, pixelHeight: 1, refresh: 60) == nil)
        precondition(FavoriteResolution(width: 1, height: 1, pixelWidth: 1, pixelHeight: 65_537, refresh: 60) == nil)
        precondition((try? DisplayPersonalization.decode(Data(repeating: 0, count: 1_048_577))) == nil)
        for json in ["{}", "{", "{\"schema\":2,\"displays\":{}}", "{\"schema\":1,\"displays\":{\"bad-id\":{\"favorites\":[]}}}"] {
            precondition((try? DisplayPersonalization.decode(Data(json.utf8))) == nil)
        }
        var value = DisplayPersonalization()
        try! value.setFavorite(uuid: uuid, mode: mode, enabled: true)
        let base = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        var entries = base["displays"] as! [String: [String: Any]]
        let entry = entries[uuid]!
        var badMode = (entry["favorites"] as! [[String: Any]])[0]
        for (key, invalid) in [("width", -1), ("pixelHeight", 0), ("refreshMilliHz", -1)] {
            var changed = badMode; changed[key] = invalid
            var broken = base; broken["displays"] = [uuid: ["favorites": [changed]]]
            precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
        }
        badMode["refreshMilliHz"] = 2_000_001
        var broken = base; broken["displays"] = [uuid: ["favorites": [badMode]]]
        precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
        for name in ["", "  Desk  ", "A\nB", String(repeating: "x", count: 41)] {
            entries[uuid] = entry; entries[uuid]?["name"] = name
            broken["displays"] = entries
            precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
        }
        broken["displays"] = [uuid: ["favorites": [mode, mode].map { try! JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }]]
        precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
        broken["displays"] = [uuid.lowercased(): entry]
        precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
    }
    static func limitsAndRemoval() {
        var value = DisplayPersonalization()
        for index in 1...32 {
            try! value.setFavorite(uuid: uuid, mode: .init(width: 1000 + index, height: 800, pixelWidth: 1000 + index, pixelHeight: 800, refresh: 60)!, enabled: true)
        }
        precondition((try? value.setFavorite(uuid: uuid, mode: mode, enabled: true)) == nil)
        try! value.setFavorite(uuid: uuid, mode: value.entry(for: uuid).favorites[0], enabled: false)
        try! value.setFavorite(uuid: uuid, mode: mode, enabled: true)
        for index in 1...63 {
            try! value.rename(uuid: String(format: "00000000-0000-4000-9000-%012d", index), name: "Screen")
        }
        precondition(value.displays.count == 64)
        precondition((try? value.rename(uuid: other, name: "Another")) == nil)
        try! value.rename(uuid: uuid, name: "Allowed existing screen")
        precondition(try! DisplayPersonalization.decode(JSONEncoder().encode(value)) == value)
        var broken = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        var displays = broken["displays"] as! [String: Any]
        displays[other] = ["name": "Excess", "favorites": []] as [String: Any]
        broken["displays"] = displays
        precondition((try? DisplayPersonalization.decode(JSONSerialization.data(withJSONObject: broken))) == nil)
    }
}
