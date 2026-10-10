import Foundation

public enum MonitorAudio {
    public static func rememberedVolume(confirmed: Double?, previous: Double?) -> Double? {
        [confirmed, previous].compactMap { $0 }.first { $0.isFinite && $0 > 0 && $0 <= 1 }
    }

    public static func toggledVolume(current: Double, remembered: Double?) -> Double {
        current > 0 ? 0 : (rememberedVolume(confirmed: nil, previous: remembered) ?? 0.25)
    }
}

public enum DDCTiming: String, CaseIterable, Sendable {
    case standard, slow
    public init(saved: String?) { self = saved.flatMap(Self.init(rawValue:)) ?? .standard }
    public var delayMS: Int { self == .slow ? 150 : 50 }
    public var title: String { self == .slow ? "Slow" : "Standard" }
}

public enum DDCControlStatus: String, Decodable, Sendable {
    case ok, unsupported, invalidReply, invalidRange, writeError, readError, notAvailable
    public var title: String {
        switch self {
        case .ok: return "Responding"
        case .unsupported: return "Not supported by monitor"
        case .invalidReply: return "No valid reply"
        case .invalidRange: return "Invalid control range"
        case .writeError: return "Request could not be sent"
        case .readError: return "Reply could not be read"
        case .notAvailable: return "No DDC route"
        }
    }
    public var guidance: String {
        switch self {
        case .ok: return "The monitor reported a valid current value and range."
        case .unsupported: return "The monitor explicitly reported this control as unsupported."
        case .invalidReply: return "Enable DDC/CI in the monitor menu, try Slow timing, then check the cable or dock."
        case .invalidRange: return "The monitor did not report a safe range. Hardware control stays unavailable."
        case .writeError, .readError: return "Try a direct connection and check DDC/CI. A dock or adapter may block communication."
        case .notAvailable: return "This connection has no unique external DDC service. Software dimming remains available."
        }
    }
}

public struct DDCControlProbe: Decodable, Sendable {
    public let status: DDCControlStatus
    public let attempts: Int
    public let current: Int?
    public let maximum: Int?
    public let errorCode: UInt32?
    public var fraction: Double? {
        guard status == .ok, let current, let maximum, maximum > 0, current >= 0, current <= maximum else { return nil }
        return Double(current) / Double(maximum)
    }
    public var summary: String {
        var text = status.title
        if let current, let maximum { text += " · \(current)/\(maximum)" }
        if attempts > 0 { text += " · \(attempts) \(attempts == 1 ? "attempt" : "attempts")" }
        if let errorCode { text += String(format: " · I/O 0x%08X", errorCode) }
        return text
    }
    fileprivate var isValid: Bool {
        guard (0...3).contains(attempts), (status == .notAvailable) == (attempts == 0) else { return false }
        if let current, !(0...65535).contains(current) { return false }
        if let maximum, !(0...65535).contains(maximum) { return false }
        return status != .ok || fraction != nil
    }
}

public enum DDCTransportKind: String, Decodable, Sendable {
    case standard, mcdp, none, ambiguous
    public var title: String {
        switch self {
        case .standard: return "External DDC service (0x37)"
        case .mcdp: return "MCDP HDMI bridge (0xB7)"
        case .none: return "No verified DDC route"
        case .ambiguous: return "DDC route is ambiguous"
        }
    }
}

public struct DDCProbe: Decodable, Sendable {
    public let schema: Int
    public let uuid: String
    public let transport: DDCTransportKind
    public let serviceCount: Int
    public let delayMS: Int
    public let brightness: DDCControlProbe
    public let volume: DDCControlProbe

    public static func parse(_ data: Data, expectedUUID: String, timing: DDCTiming) -> DDCProbe? {
        guard let probe = try? JSONDecoder().decode(Self.self, from: data), probe.schema == 1,
              let expected = UUID(uuidString: expectedUUID), UUID(uuidString: probe.uuid) == expected,
              probe.delayMS == timing.delayMS, probe.brightness.isValid, probe.volume.isValid else { return nil }
        let routed = probe.transport == .standard || probe.transport == .mcdp
        guard routed ? probe.serviceCount == 1 : (probe.transport == .none ? probe.serviceCount == 0 : probe.serviceCount >= 0),
              routed ? (probe.brightness.status != .notAvailable && probe.volume.status != .notAvailable) :
                       (probe.brightness.status == .notAvailable && probe.volume.status == .notAvailable) else { return nil }
        return probe
    }

    /// A deliberate allowlist: identities, raw output, names and paths never enter the report.
    public var diagnosticLines: [String] {
        ["DDC route: \(transport.title)", "Matching services: \(serviceCount)", "Read wait: \(delayMS) ms",
         "Brightness: \(brightness.summary)", "Volume: \(volume.summary)"]
    }
}

public enum ControlMath {
    public static let softwareThreshold = 0.2

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(1, max(0, value))
    }

    public static func combined(_ value: Double) -> (hardware: Double, software: Double) {
        let value = clamp(value)
        if value < softwareThreshold {
            return (0, max(0.03, value / softwareThreshold))
        }
        return ((value - softwareThreshold) / (1 - softwareThreshold), 1)
    }

    public static func combinedValue(hardware: Double, software: Double = 1) -> Double {
        software < 1 ? clamp(software) * softwareThreshold : softwareThreshold + clamp(hardware) * (1 - softwareThreshold)
    }

    public static func rawValue(fraction: Double, maximum: Int) -> Int {
        Int((clamp(fraction) * Double(max(1, min(65535, maximum)))).rounded())
    }

    public static func parseDDC(_ output: String) -> Int? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (0...65535).contains(value) else { return nil }
        return value
    }

    public static func mayDisconnect(isEnabled: Bool, activeCount: Int, pending: Bool) -> Bool {
        !pending && (!isEnabled || activeCount > 1)
    }
}

public struct ModeDescriptor: Equatable, Sendable {
    public let id: Int32
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let refresh: Double
    public var hiDPI: Bool { pixelWidth > width }

    public init(id: Int32, width: Int, height: Int, pixelWidth: Int, refresh: Double) {
        self.id = id; self.width = width; self.height = height
        self.pixelWidth = pixelWidth; self.refresh = refresh
    }
}

public enum ModeSelection {
    /// One slider stop per logical size. Preserve the exact current mode; otherwise
    /// prefer its density and refresh rate so dragging does not arbitrarily switch either.
    public static func sliderModes(_ modes: [ModeDescriptor], current: ModeDescriptor?) -> [ModeDescriptor] {
        let groups = Dictionary(grouping: modes) { "\($0.width)x\($0.height)" }
        return groups.values.compactMap { group in
            group.sorted { a, b in
                if a.id == b.id { return false }
                if a.id == current?.id { return true }
                if b.id == current?.id { return false }
                let preferredDensity = current?.hiDPI ?? true
                if a.hiDPI != b.hiDPI { return a.hiDPI == preferredDensity }
                let target = current?.refresh ?? 60
                let da = abs(a.refresh - target), db = abs(b.refresh - target)
                if da != db { return da < db }
                return a.id < b.id
            }.first
        }.sorted { ($0.width * $0.height, $0.width, $0.height) < ($1.width * $1.height, $1.width, $1.height) }
    }
}

public struct DisplayIdentity: Codable, Equatable, Sendable {
    public let displayID: UInt32
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public init(displayID: UInt32, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.displayID = displayID; self.vendor = vendor; self.model = model; self.serial = serial
    }
    public func matchesHardware(_ other: DisplayIdentity) -> Bool {
        vendor != 0 && model != 0 && vendor == other.vendor && model == other.model && serial == other.serial
    }
    public static func resolve(_ expected: DisplayIdentity, among candidates: [DisplayIdentity]) -> UInt32? {
        let matches = candidates.filter { expected.matchesHardware($0) }
        // An ambiguous pair of identical monitors without unique serial numbers
        // must never cause the app to reconnect or disconnect the wrong screen.
        return matches.count == 1 ? matches[0].displayID : nil
    }
}


public struct DisplayConnectionState: Sendable {
    public let uuid: String
    public let builtIn: Bool
    public let online: Bool
    public let active: Bool

    public init(uuid: String, builtIn: Bool, online: Bool, active: Bool) {
        self.uuid = uuid; self.builtIn = builtIn
        self.online = online; self.active = active
    }
}

public enum BuiltInDisplayRecovery {
    /// Only restore a panel disabled by this app, after its replacement disappears.
    /// An unknown lid state is not permission to override clamshell behavior.
    public static func candidates(_ displays: [DisplayConnectionState], owned: Set<String>,
                                  lidClosed: Bool?, sleeping: Bool, connectionBusy: Bool,
                                  physicalExternalLost: Bool = false) -> [String] {
        guard !owned.isEmpty, lidClosed == false, !sleeping, !connectionBusy,
              physicalExternalLost || !displays.contains(where: { !$0.builtIn && $0.online && $0.active }) else { return [] }
        return displays.filter { $0.builtIn && owned.contains($0.uuid) && !($0.online && $0.active) }
            .map(\.uuid)
    }
}

public enum ExternalLinkState {
    /// Hardware port events can change before WindowServer updates its display list.
    public static func active(hints: [String: Any]?, events: [[String: Any]]) -> Bool? {
        var active: Bool?
        for event in events {
            guard let payload = event["EventPayload"] as? [String: Any] else { continue }
            if let action = payload["Action"] as? String {
                switch action {
                case "Plug", "DisplayRequest": active = true
                case "Unplug", "DisplayRelease": active = false
                default: break
                }
            }
            if let state = payload["State"] as? String,
               ["SinkActive", "Activate", "LinkRate", "LaneCount"].contains(state),
               let value = payload["Value"] as? NSNumber {
                active = value.intValue > 0
            }
        }
        if let active { return active }
        guard let hints else { return nil }
        if let valid = hints["Valid"] as? Bool, !valid { return false }
        guard let width = hints["MaxW"] as? NSNumber, let height = hints["MaxH"] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { return nil }
        return true
    }
}
