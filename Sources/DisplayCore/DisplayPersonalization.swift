import Foundation

/// Geometry is stable across discovery; native mode IDs are not persisted.
public struct FavoriteResolution: Codable, Hashable, Identifiable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshMilliHz: Int
    public var id: String { "\(width)x\(height):\(pixelWidth)x\(pixelHeight):\(refreshMilliHz)" }
    public var title: String { "\(width) × \(height)" }
    public var detail: String {
        let density = pixelWidth > width ? "HiDPI" : "Standard"
        guard refreshMilliHz > 0 else { return density }
        let refresh = (Double(refreshMilliHz) / 1000).formatted(.number.precision(.fractionLength(0...3)))
        return "\(density) · \(refresh) Hz"
    }
    public init?(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double) {
        guard refresh.isFinite, (0...2000).contains(refresh) else { return nil }
        self.width = width; self.height = height; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        refreshMilliHz = Int((refresh * 1000).rounded())
        guard isValid else { return nil }
    }
    fileprivate var isValid: Bool {
        [width, height, pixelWidth, pixelHeight].allSatisfy { (1...65_536).contains($0) } &&
        (0...2_000_000).contains(refreshMilliHz)
    }
}

public enum PersonalizationError: LocalizedError {
    case name, limit, favorites, invalidData
    public var errorDescription: String? {
        switch self {
        case .name: return "Use a name of up to 40 characters without line breaks or control characters."
        case .limit: return "You can personalize up to 64 displays."
        case .favorites: return "You can save up to 32 favorite resolutions per display."
        case .invalidData: return "Saved display settings could not be read. The original data has been kept."
        }
    }
}

public struct DisplayPersonalization: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public fileprivate(set) var name: String?
        public fileprivate(set) var favorites: [FavoriteResolution] = []
    }
    public let schema: Int
    public private(set) var displays: [String: Entry]
    public init() { schema = 1; displays = [:] }
    public func entry(for uuid: String) -> Entry { displays[uuid.uppercased()] ?? Entry() }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == 1, value.displays.count <= 64 else { throw PersonalizationError.invalidData }
        for (uuid, entry) in value.displays {
            guard UUID(uuidString: uuid) != nil, uuid == uuid.uppercased(),
                  entry.favorites.count <= 32, entry.favorites.allSatisfy(\.isValid),
                  Set(entry.favorites).count == entry.favorites.count else { throw PersonalizationError.invalidData }
            if let name = entry.name {
                guard !name.isEmpty, (try? normalizedName(name)) == name else { throw PersonalizationError.invalidData }
            }
        }
        return value
    }

    public mutating func rename(uuid: String, name: String) throws {
        let name = try Self.normalizedName(name)
        try update(uuid: uuid) { $0.name = name.isEmpty ? nil : name }
    }
    public mutating func setFavorite(uuid: String, mode: FavoriteResolution, enabled: Bool) throws {
        guard mode.isValid else { throw PersonalizationError.invalidData }
        try update(uuid: uuid) { entry in
            if enabled && !entry.favorites.contains(mode) {
                guard entry.favorites.count < 32 else { throw PersonalizationError.favorites }
                entry.favorites.append(mode)
            } else if !enabled { entry.favorites.removeAll { $0 == mode } }
        }
    }
    private mutating func update(uuid: String, edit: (inout Entry) throws -> Void) throws {
        guard UUID(uuidString: uuid) != nil else { throw PersonalizationError.invalidData }
        let key = uuid.uppercased()
        var entry = entry(for: key)
        try edit(&entry)
        if entry.name == nil && entry.favorites.isEmpty { displays.removeValue(forKey: key); return }
        guard displays[key] != nil || displays.count < 64 else { throw PersonalizationError.limit }
        displays[key] = entry
    }
    private static func normalizedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 40, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PersonalizationError.name
        }
        return name
    }
}
