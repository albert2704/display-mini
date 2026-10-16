import Foundation

/// A target captured while this process can identify a built-in panel exactly.
/// Keep it only for the owned disconnection that produced it, never in storage.
public struct BuiltInReconnectTarget: Equatable, Sendable {
    public let uuid: String
    public let identity: DisplayIdentity

    public init?(uuid: String, currentUUID: String?, identity: DisplayIdentity, builtinFlag: Int32) {
        guard UUID(uuidString: uuid) != nil, currentUUID == uuid,
              builtinFlag == 1, Self.valid(identity) else { return nil }
        self.uuid = uuid
        self.identity = identity
    }

    /// SkyLight may omit a disabled panel even while direct queries still identify
    /// its captured ID. This path can only reconnect that same owned panel.
    public func resolve(enable: Bool, owned: Bool, currentUUID: String?,
                        current: DisplayIdentity, builtinFlag: Int32) -> UInt32? {
        guard enable, owned, builtinFlag == 1,
              current.displayID == identity.displayID,
              currentUUID == nil || currentUUID == uuid,
              Self.valid(current), identity.matchesHardware(current) else { return nil }
        return current.displayID
    }

    private static func valid(_ identity: DisplayIdentity) -> Bool {
        identity.displayID != 0 && identity.displayID != UInt32.max &&
        identity.vendor != 0 && identity.vendor != UInt32.max &&
        identity.model != 0 && identity.model != UInt32.max &&
        identity.serial != UInt32.max
    }
}
