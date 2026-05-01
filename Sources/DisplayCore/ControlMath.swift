import Foundation

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
