import Foundation

/// A built-in layout target captured before this process successfully disables it.
/// Keep this only for that owned disconnection; never reconstruct it from storage.
public struct CapturedPanelReconnect: Equatable, Sendable {
    public let uuid: String
    public let identity: DisplayIdentity

    public init?(uuid: String, currentUUID: String?, identity: DisplayIdentity, builtinFlag: Int32) {
        guard UUID(uuidString: uuid) != nil, currentUUID == uuid, builtinFlag == 1,
              identity.displayID != 0, identity.displayID != .max,
              Self.validHardwareField(identity.vendor), Self.validHardwareField(identity.model),
              identity.serial != .max else { return nil }
        self.uuid = uuid
        self.identity = identity
    }

    /// Resolve only a reconnect after the same kernel panel accepted a wake.
    /// The caller consumes that acceptance before one enable transaction and
    /// permanently invalidates this capture if it observes display-ID reuse.
    public func resolve(owned: Bool, kernelMatches: Bool, wakeAccepted: Bool, isListed: Bool,
                        currentUUID: String?, current: DisplayIdentity, builtinFlag: Int32,
                        coreDisplayMatches: Bool?) -> UInt32? {
        guard owned, kernelMatches, wakeAccepted, !isListed,
              !conflicts(currentUUID: currentUUID, current: current, builtinFlag: builtinFlag,
                         coreDisplayMatches: coreDisplayMatches) else { return nil }
        return identity.displayID
    }

    /// A contradiction invalidates the capture for the rest of its lifetime,
    /// even if a later observation has only unknown identity fields.
    public func conflicts(currentUUID: String?, current: DisplayIdentity, builtinFlag: Int32,
                          coreDisplayMatches: Bool?) -> Bool {
        guard current.displayID == identity.displayID,
              builtinFlag == -1 || builtinFlag == 1,
              currentUUID == nil || currentUUID == uuid,
              coreDisplayMatches != false else { return true }
        // An omitted panel can return unknown CG identity values. Every field
        // that is available remains a veto if it contradicts the captured panel.
        guard !Self.validHardwareField(current.vendor) || current.vendor == identity.vendor,
              !Self.validHardwareField(current.model) || current.model == identity.model,
              current.serial == .max || current.serial == identity.serial else { return true }
        return false
    }

    private static func validHardwareField(_ value: UInt32) -> Bool {
        value != 0 && value != .max
    }
}
