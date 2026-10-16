import DisplayCore

enum CapturedPanelReconnectTests {
    static func run() {
        let uuid = "00000000-0000-4000-8000-00000000C001"
        let otherUUID = "00000000-0000-4000-8000-00000000C002"
        func panel(id: UInt32 = 1, vendor: UInt32 = 1552,
                   model: UInt32 = 41041, serial: UInt32 = 100002) -> DisplayIdentity {
            .init(displayID: id, vendor: vendor, model: model, serial: serial)
        }
        let identity = panel()
        let unknown = panel(vendor: .max, model: .max, serial: .max)
        let target = CapturedPanelReconnect(uuid: uuid, currentUUID: uuid, identity: identity, builtinFlag: 1)!
        func resolve(owned: Bool = true, kernel: Bool = true, woke: Bool = true,
                     listed: Bool = false, currentUUID: String? = nil,
                     current: DisplayIdentity = unknown, builtinFlag: Int32 = -1,
                     coreDisplayMatches: Bool? = nil) -> UInt32? {
            target.resolve(owned: owned, kernelMatches: kernel, wakeAccepted: woke, isListed: listed,
                currentUUID: currentUUID, current: current, builtinFlag: builtinFlag,
                coreDisplayMatches: coreDisplayMatches)
        }
        func conflicts(currentUUID: String? = nil, current: DisplayIdentity = unknown,
                       builtinFlag: Int32 = -1, coreDisplayMatches: Bool? = nil) -> Bool {
            target.conflicts(currentUUID: currentUUID, current: current, builtinFlag: builtinFlag,
                             coreDisplayMatches: coreDisplayMatches)
        }

        // Enumeration can permanently discard a capture before any reconnect.
        // Unknown values are not evidence of reuse; any contradiction is.
        precondition(!conflicts())
        precondition(!conflicts(currentUUID: uuid, current: identity, builtinFlag: 1, coreDisplayMatches: true))
        precondition(!conflicts(current: panel(vendor: 0, model: 0, serial: .max)))
        precondition(conflicts(current: panel(id: 2, vendor: .max, model: .max, serial: .max)))
        precondition(conflicts(currentUUID: otherUUID))
        precondition(conflicts(currentUUID: ""))
        precondition(conflicts(coreDisplayMatches: false))
        precondition(conflicts(current: panel(vendor: 7789, model: .max, serial: .max)))
        precondition(conflicts(current: panel(vendor: .max, model: 23491, serial: .max)))
        precondition(conflicts(current: panel(vendor: .max, model: .max, serial: 100003)))
        precondition(conflicts(current: panel(vendor: .max, model: .max, serial: 0)))
        for flag in [Int32(0), -2, 2, .max, .min] {
            precondition(conflicts(builtinFlag: flag))
        }

        // Physical failure: the panel is absent and all direct CG queries are
        // unknown, while its captured kernel object still verifies and wakes.
        precondition(resolve() == identity.displayID)
        precondition(resolve(coreDisplayMatches: true) == identity.displayID)
        precondition(resolve(current: panel(vendor: 0, model: 0, serial: .max)) == identity.displayID)
        precondition(resolve(current: panel(vendor: 0, model: identity.model, serial: .max)) == identity.displayID)
        precondition(resolve(currentUUID: uuid, current: identity, builtinFlag: 1) == identity.displayID)
        precondition(resolve(owned: false) == nil)
        precondition(resolve(kernel: false) == nil)
        precondition(resolve(woke: false) == nil)
        precondition(resolve(listed: true) == nil)
        precondition(resolve(current: panel(id: 2, vendor: .max, model: .max, serial: .max)) == nil)
        precondition(resolve(currentUUID: otherUUID) == nil)
        precondition(resolve(currentUUID: "") == nil)
        precondition(resolve(coreDisplayMatches: false) == nil)

        // One contradictory live field is enough, even when the others vanished.
        precondition(resolve(current: panel(vendor: 7789, model: .max, serial: .max)) == nil)
        precondition(resolve(current: panel(vendor: .max, model: 23491, serial: .max)) == nil)
        precondition(resolve(current: panel(vendor: .max, model: .max, serial: 100003)) == nil)
        precondition(resolve(current: panel(vendor: .max, model: .max, serial: 0)) == nil)
        for flag in [Int32(0), -2, 2, .max, .min] {
            precondition(resolve(builtinFlag: flag) == nil)
        }

        for flag in [Int32(0), -1, 2] {
            precondition(CapturedPanelReconnect(uuid: uuid, currentUUID: uuid,
                                                identity: identity, builtinFlag: flag) == nil)
        }
        precondition(CapturedPanelReconnect(uuid: "invalid", currentUUID: "invalid", identity: identity, builtinFlag: 1) == nil)
        precondition(CapturedPanelReconnect(uuid: uuid, currentUUID: nil, identity: identity, builtinFlag: 1) == nil)
        precondition(CapturedPanelReconnect(uuid: uuid, currentUUID: otherUUID, identity: identity, builtinFlag: 1) == nil)
        for invalid in [panel(id: 0), panel(id: .max), panel(vendor: 0), panel(vendor: .max),
                        panel(model: 0), panel(model: .max), panel(serial: .max)] {
            precondition(CapturedPanelReconnect(uuid: uuid, currentUUID: uuid,
                                                identity: invalid, builtinFlag: 1) == nil)
        }
        let noSerial = panel(serial: 0)
        let noSerialTarget = CapturedPanelReconnect(uuid: uuid, currentUUID: uuid, identity: noSerial, builtinFlag: 1)!
        precondition(!noSerialTarget.conflicts(currentUUID: nil, current: noSerial,
                                              builtinFlag: -1, coreDisplayMatches: nil))
        precondition(!noSerialTarget.conflicts(currentUUID: nil, current: unknown,
                                              builtinFlag: -1, coreDisplayMatches: nil))
        precondition(noSerialTarget.conflicts(currentUUID: nil, current: identity,
                                             builtinFlag: -1, coreDisplayMatches: nil))
        precondition(noSerialTarget.resolve(owned: true, kernelMatches: true, wakeAccepted: true,
            isListed: false, currentUUID: nil, current: noSerial, builtinFlag: -1, coreDisplayMatches: nil) == 1)
        precondition(noSerialTarget.resolve(owned: true, kernelMatches: true, wakeAccepted: true,
            isListed: false, currentUUID: nil, current: unknown, builtinFlag: -1, coreDisplayMatches: nil) == 1)
        precondition(noSerialTarget.resolve(owned: true, kernelMatches: true, wakeAccepted: true,
            isListed: false, currentUUID: nil, current: identity, builtinFlag: -1, coreDisplayMatches: nil) == nil)
        print("Passed captured panel reconnect checks (missing CG identity, kernel witness, ownership, wake, conflicts and invalid capture).")
    }
}
