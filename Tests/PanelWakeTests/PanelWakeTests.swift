import ColorSync
import CoreGraphics
import Foundation

@main struct PanelWakeTests {
    static func main() {
        precondition(BuiltInPanelWake.runHelper(arguments: []) == nil)
        precondition(BuiltInPanelWake.runHelper(arguments: ["--unrelated-mode"]) == nil)
        precondition(BuiltInPanelWake.runHelper(arguments: ["--wake-built-in-panel=1"]) == nil)

        // Every recognized request here fails before framebuffer Open or power.
        let invalidArguments: [[String]] = [
            [], [""], ["zero"], ["0"], [String(UInt64.max)],
            ["-1"], ["+1"], ["01"], [" 1"], ["1 "], ["1\n"],
            ["1", "extra"]
        ]
        for arguments in invalidArguments {
            precondition(BuiltInPanelWake.runHelper(arguments: ["--wake-built-in-panel"] + arguments) == 2)
        }
        // This impossible registry ID cannot identify a live kernel service.
        // Never invoke helper mode with an entry ID discovered from hardware.
        precondition(BuiltInPanelWake.runHelper(arguments: ["--wake-built-in-panel", String(UInt64.max - 1)]) == 3)

        let fixtureUUID = "00000000-0000-4000-8000-00000000D001"
        precondition(BuiltInPanelTarget.capture(displayID: 0, expectedUUID: fixtureUUID) == nil)
        precondition(BuiltInPanelTarget.capture(displayID: .max, expectedUUID: fixtureUUID) == nil)
        precondition(BuiltInPanelTarget.capture(displayID: 1, expectedUUID: "invalid") == nil)

        // On a machine with an online built-in panel, also prove that a valid
        // but different UUID cannot capture its framebuffer. This only reads CG.
        var ids = [UInt32](repeating: 0, count: 64), count: UInt32 = 0
        if CGGetOnlineDisplayList(64, &ids, &count) == .success {
            for id in ids.prefix(Int(min(count, 64))) where CGDisplayIsBuiltin(id) == 1 {
                guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
                let actualUUID = CFUUIDCreateString(nil, value) as String
                let wrongUUID = actualUUID == fixtureUUID ? "00000000-0000-4000-8000-00000000D002" : fixtureUUID
                precondition(BuiltInPanelTarget.capture(displayID: id, expectedUUID: wrongUUID) == nil)
            }
        }
        print("Passed panel wake helper argument, missing-service and capture rejection checks (no framebuffer Open or power calls).")
    }
}
