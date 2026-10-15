import Foundation
import DisplayCore

enum BrightnessSelectionTests {
    static func run() {
        let first = "00000000-0000-4000-8000-00000000B001"
        let second = "00000000-0000-4000-8000-00000000B002"
        precondition(BrightnessLinkSelection().includes(first), "Missing preferences retain all-screen linking")
        let empty = BrightnessLinkSelection(mode: .selected)
        precondition(!empty.includes(first), "Empty membership must never mean all screens")
        let selected = BrightnessLinkSelection(mode: .selected, displayUUIDs: [first])
        precondition(selected.includes(first.lowercased()) && !selected.includes(second))
        precondition(try! BrightnessLinkSelection.decode(JSONEncoder().encode(selected)) == selected)
        for data in [Data("{".utf8), Data("{\"schema\":2,\"mode\":\"all\",\"displayUUIDs\":[]}".utf8),
                     Data("{\"schema\":1,\"mode\":\"selected\",\"displayUUIDs\":[\"bad\"]}".utf8)] {
            precondition((try? BrightnessLinkSelection.decode(data)) == nil)
        }
        print("Passed brightness membership validation, migration, empty selection and identity checks.")
    }
}
