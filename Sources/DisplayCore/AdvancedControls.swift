import Foundation

public struct AdvancedDDCProbe: Decodable, Sendable {
    public let schema: Int
    public let uuid: String
    public let transport: DDCTransportKind
    public let serviceCount: Int
    public let delayMS: Int
    public let contrast: DDCControlProbe
    public let input: DDCControlProbe

    public var currentInput: Int? { input.status == .ok ? input.current : nil }

    public static func parse(_ data: Data, expectedUUID: String, timing: DDCTiming) -> Self? {
        guard data.count <= 65_536,
              let probe = try? JSONDecoder().decode(Self.self, from: data), probe.schema == 1,
              let expected = UUID(uuidString: expectedUUID), UUID(uuidString: probe.uuid) == expected,
              probe.delayMS == timing.delayMS, probe.contrast.isValid(continuous: true),
              probe.input.isValid(continuous: false) else { return nil }
        let routed = probe.transport == .standard || probe.transport == .mcdp
        guard routed ? probe.serviceCount == 1 : (probe.transport == .none ? probe.serviceCount == 0 : probe.serviceCount >= 0),
              routed ? (probe.contrast.status != .notAvailable && probe.input.status != .notAvailable) :
                       (probe.contrast.status == .notAvailable && probe.input.status == .notAvailable) else { return nil }
        return probe
    }
}

/// Common MCCS codes, not a list of ports advertised by a particular monitor.
public enum MonitorInput: Int, CaseIterable, Identifiable, Sendable {
    case vga = 1, dvi1 = 3, dvi2 = 4, displayPort1 = 15, displayPort2 = 16, hdmi1 = 17, hdmi2 = 18
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .vga: return "VGA"
        case .dvi1: return "DVI 1"
        case .dvi2: return "DVI 2"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        }
    }
    public static func title(for value: Int) -> String {
        Self(rawValue: value)?.title ?? String(format: "Monitor input 0x%04X", value)
    }
}

public extension FavoriteResolution {
    var refreshTitle: String {
        guard refreshMilliHz > 0 else { return "Variable / system" }
        return "\((Double(refreshMilliHz) / 1000).formatted(.number.precision(.fractionLength(0...3)))) Hz"
    }
    func hasSameGeometry(as other: Self) -> Bool {
        width == other.width && height == other.height && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
    }
}

public enum RefreshRateSelection {
    public static func options(_ modes: [FavoriteResolution], current: FavoriteResolution) -> [FavoriteResolution] {
        Array(Set(modes.filter { $0.hasSameGeometry(as: current) })).sorted { $0.refreshMilliHz < $1.refreshMilliHz }
    }
}
