import Foundation
import Carbon

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32
    static let control = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let shift = Self(rawValue: 4)
    static let command = Self(rawValue: 8)
    static let all: Self = [.control, .option, .shift, .command]
    var carbon: UInt32 {
        (contains(.control) ? UInt32(controlKey) : 0) |
        (contains(.option) ? UInt32(optionKey) : 0) |
        (contains(.shift) ? UInt32(shiftKey) : 0) |
        (contains(.command) ? UInt32(cmdKey) : 0)
    }
    var label: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") +
        (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

struct ShortcutKey: Identifiable {
    let id: UInt32
    let label: String
    private init(_ code: Int, _ label: String) { id = UInt32(code); self.label = label }
    // These are physical ANSI key positions, as used by RegisterEventHotKey.
    static let choices: [Self] = [
        .init(kVK_UpArrow, "↑"), .init(kVK_DownArrow, "↓"), .init(kVK_LeftArrow, "←"), .init(kVK_RightArrow, "→"),
        .init(kVK_ANSI_A, "A"), .init(kVK_ANSI_B, "B"), .init(kVK_ANSI_C, "C"), .init(kVK_ANSI_D, "D"),
        .init(kVK_ANSI_E, "E"), .init(kVK_ANSI_F, "F"), .init(kVK_ANSI_G, "G"), .init(kVK_ANSI_H, "H"),
        .init(kVK_ANSI_I, "I"), .init(kVK_ANSI_J, "J"), .init(kVK_ANSI_K, "K"), .init(kVK_ANSI_L, "L"),
        .init(kVK_ANSI_M, "M"), .init(kVK_ANSI_N, "N"), .init(kVK_ANSI_O, "O"), .init(kVK_ANSI_P, "P"),
        .init(kVK_ANSI_Q, "Q"), .init(kVK_ANSI_R, "R"), .init(kVK_ANSI_S, "S"), .init(kVK_ANSI_T, "T"),
        .init(kVK_ANSI_U, "U"), .init(kVK_ANSI_V, "V"), .init(kVK_ANSI_W, "W"), .init(kVK_ANSI_X, "X"),
        .init(kVK_ANSI_Y, "Y"), .init(kVK_ANSI_Z, "Z"),
        .init(kVK_ANSI_0, "0"), .init(kVK_ANSI_1, "1"), .init(kVK_ANSI_2, "2"), .init(kVK_ANSI_3, "3"),
        .init(kVK_ANSI_4, "4"), .init(kVK_ANSI_5, "5"), .init(kVK_ANSI_6, "6"), .init(kVK_ANSI_7, "7"),
        .init(kVK_ANSI_8, "8"), .init(kVK_ANSI_9, "9"),
        .init(kVK_F1, "F1"), .init(kVK_F2, "F2"), .init(kVK_F3, "F3"), .init(kVK_F4, "F4"),
        .init(kVK_F5, "F5"), .init(kVK_F6, "F6"), .init(kVK_F7, "F7"), .init(kVK_F8, "F8"),
        .init(kVK_F9, "F9"), .init(kVK_F10, "F10"), .init(kVK_F11, "F11"), .init(kVK_F12, "F12"),
        .init(kVK_Space, "Space"), .init(kVK_Home, "Home"), .init(kVK_End, "End"),
        .init(kVK_PageUp, "Page Up"), .init(kVK_PageDown, "Page Down")
    ]
    struct Group: Identifiable {
        let title: String
        let keys: [ShortcutKey]
        var id: String { title }
    }
    static let groups: [Group] = [
        .init(title: "Arrows", keys: Array(choices[0..<4])),
        .init(title: "Letters A–M", keys: Array(choices[4..<17])),
        .init(title: "Letters N–Z", keys: Array(choices[17..<30])),
        .init(title: "Numbers", keys: Array(choices[30..<40])),
        .init(title: "Function keys", keys: Array(choices[40..<52])),
        .init(title: "Navigation", keys: Array(choices[52...]))
    ]
}

struct ShortcutBinding: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: ShortcutModifiers
    var label: String { modifiers.label + (ShortcutKey.choices.first { $0.id == keyCode }?.label ?? "?") }
    static let recovery = Self(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .option, .command])
    var isValid: Bool {
        modifiers.rawValue & ~ShortcutModifiers.all.rawValue == 0 &&
        !modifiers.intersection([.control, .command]).isEmpty &&
        ShortcutKey.choices.contains { $0.id == keyCode }
    }
}

enum ShortcutPreferenceError: LocalizedError {
    case invalid, duplicate(String), reserved, unreadable
    var errorDescription: String? {
        switch self {
        case .invalid: return "Choose a listed key and include Control or Command."
        case .duplicate(let action): return "This shortcut is already assigned to \(action). Choose another combination."
        case .reserved: return "⌃⌥⌘R is reserved for display recovery."
        case .unreadable: return "Saved shortcut bindings could not be read. Defaults are active; the original data is kept until you save or reset."
        }
    }
}

struct ShortcutPreferences: Codable, Equatable {
    let schema: Int
    private var bindings: [UInt32: ShortcutBinding]
    init() {
        schema = 1
        bindings = Dictionary(uniqueKeysWithValues: DisplayShortcut.allCases.map { ($0.rawValue, $0.defaultBinding) })
    }
    subscript(_ action: DisplayShortcut) -> ShortcutBinding { bindings[action.rawValue] ?? action.defaultBinding }
    mutating func set(_ action: DisplayShortcut, binding: ShortcutBinding) throws {
        guard binding.isValid else { throw ShortcutPreferenceError.invalid }
        guard action == .restore || binding != .recovery else { throw ShortcutPreferenceError.reserved }
        if let other = DisplayShortcut.allCases.first(where: { $0 != action && self[$0] == binding }) {
            throw ShortcutPreferenceError.duplicate(other.title)
        }
        bindings[action.rawValue] = binding
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384, let saved = try? JSONDecoder().decode(Self.self, from: data), saved.schema == 1,
              Set(saved.bindings.keys) == Set(DisplayShortcut.allCases.map(\.rawValue)),
              Set(saved.bindings.values).count == DisplayShortcut.allCases.count,
              saved.bindings.values.allSatisfy(\.isValid),
              DisplayShortcut.allCases.allSatisfy({ $0 == .restore || saved[$0] != .recovery }) else {
            throw ShortcutPreferenceError.unreadable
        }
        return saved
    }
}
