import Foundation

public struct BrightnessLinkSelection: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case all, selected
        public var title: String { self == .all ? "All screens" : "Selected screens" }
    }
    public private(set) var schema = 1
    public var mode: Mode
    public var displayUUIDs: Set<String>

    public init(mode: Mode = .all, displayUUIDs: Set<String> = []) {
        self.mode = mode
        self.displayUUIDs = displayUUIDs
    }

    public func includes(_ identity: String) -> Bool {
        mode == .all || UUID(uuidString: identity).map { displayUUIDs.contains($0.uuidString) } == true
    }

    public func validated() throws -> Self {
        guard schema == 1, displayUUIDs.count <= 64,
              displayUUIDs.allSatisfy({ UUID(uuidString: $0)?.uuidString == $0 }) else {
            throw StorageError.invalid
        }
        return self
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384 else { throw StorageError.invalid }
        do { return try JSONDecoder().decode(Self.self, from: data).validated() }
        catch { throw StorageError.invalid }
    }

    public enum StorageError: LocalizedError {
        case invalid
        public var errorDescription: String? {
            "The saved brightness selection could not be read. Linking is paused until you reset it."
        }
    }
}
