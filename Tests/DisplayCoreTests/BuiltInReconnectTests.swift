import DisplayCore

enum BuiltInReconnectTests {
    static func run() {
        let uuid = "00000000-0000-4000-8000-00000000C001"
        let otherUUID = "00000000-0000-4000-8000-00000000C002"
        // Synthetic hardware values; no physical monitor identity is recorded.
        func panel(id: UInt32 = 1, vendor: UInt32 = 1552,
                   model: UInt32 = 41041, serial: UInt32 = 100002) -> DisplayIdentity {
            .init(displayID: id, vendor: vendor, model: model, serial: serial)
        }
        let original = panel()
        let target = BuiltInReconnectTarget(uuid: uuid, currentUUID: uuid,
                                            identity: original, builtinFlag: 1)!
        func resolve(enable: Bool = true, owned: Bool = true, currentUUID: String? = nil,
                     current: DisplayIdentity = original, builtinFlag: Int32 = 1) -> UInt32? {
            target.resolve(enable: enable, owned: owned, currentUUID: currentUUID,
                           current: current, builtinFlag: builtinFlag)
        }

        // Reproduce a private list containing only the external replacement.
        // Generic lookup cannot find the panel; direct verified identity can.
        let external = DisplayIdentity(displayID: 2, vendor: 7789, model: 23491, serial: 100003)
        precondition(DisplayIdentity.resolve(original, among: [external]) == nil)
        precondition(resolve() == 1)
        precondition(resolve(currentUUID: uuid) == 1)
        precondition(resolve(enable: false) == nil)
        precondition(resolve(owned: false) == nil)
        precondition(resolve(current: panel(id: 3)) == nil)
        precondition(resolve(currentUUID: otherUUID) == nil)
        precondition(resolve(current: panel(vendor: 7789)) == nil)
        precondition(resolve(current: panel(model: 23491)) == nil)
        precondition(resolve(current: panel(serial: 100004)) == nil)
        precondition(resolve(current: external, builtinFlag: 0) == nil)
        for flag in [Int32(0), -1, 2] {
            precondition(resolve(builtinFlag: flag) == nil)
            precondition(BuiltInReconnectTarget(uuid: uuid, currentUUID: uuid,
                                                identity: original, builtinFlag: flag) == nil)
        }

        precondition(BuiltInReconnectTarget(uuid: "invalid", currentUUID: "invalid",
                                            identity: original, builtinFlag: 1) == nil)
        precondition(BuiltInReconnectTarget(uuid: uuid, currentUUID: nil,
                                            identity: original, builtinFlag: 1) == nil)
        precondition(BuiltInReconnectTarget(uuid: uuid, currentUUID: otherUUID,
                                            identity: original, builtinFlag: 1) == nil)
        for invalid in [panel(id: 0), panel(id: .max), panel(vendor: 0), panel(vendor: .max),
                        panel(model: 0), panel(model: .max), panel(serial: .max)] {
            precondition(BuiltInReconnectTarget(uuid: uuid, currentUUID: uuid,
                                                identity: invalid, builtinFlag: 1) == nil)
            precondition(resolve(current: invalid) == nil)
        }

        // A serial number of zero is valid when a panel has no encoded serial.
        let noSerial = panel(serial: 0)
        let noSerialTarget = BuiltInReconnectTarget(uuid: uuid, currentUUID: uuid,
                                                    identity: noSerial, builtinFlag: 1)!
        precondition(noSerialTarget.resolve(enable: true, owned: true, currentUUID: nil,
                                           current: noSerial, builtinFlag: 1) == 1)
        precondition(resolve(current: noSerial) == nil)
        precondition(noSerialTarget.resolve(enable: true, owned: true, currentUUID: nil,
                                           current: original, builtinFlag: 1) == nil)
        print("Passed built-in reconnect capture, omitted-list recovery, ownership, identity and invalid-value checks.")
    }
}
