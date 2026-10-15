import Foundation

public enum PresetScheduleRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, weekdays, weekends
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        }
    }
    public func includes(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .daily: return true
        case .weekdays: return !calendar.isDateInWeekend(date)
        case .weekends: return calendar.isDateInWeekend(date)
        }
    }
}

public struct PresetSchedule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var presetID: UUID
    public var hour: Int
    public var minute: Int
    public var recurrence: PresetScheduleRecurrence
    public var enabled: Bool

    public init(id: UUID = UUID(), presetID: UUID, hour: Int, minute: Int,
                recurrence: PresetScheduleRecurrence = .daily, enabled: Bool = false) {
        self.id = id; self.presetID = presetID; self.hour = hour; self.minute = minute
        self.recurrence = recurrence; self.enabled = enabled
    }
    public var timeTitle: String { String(format: "%02d:%02d", hour, minute) }
    public var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }

    /// Strict matching skips nonexistent spring-forward times. The first repeated time is canonical.
    public func occurrence(on date: Date, calendar: Calendar) -> Date? {
        guard isValid, recurrence.includes(date, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: date)
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        guard let result = calendar.nextDate(after: start.addingTimeInterval(-1), matching: components,
                                             matchingPolicy: .strict, repeatedTimePolicy: .first,
                                             direction: .forward), calendar.isDate(result, inSameDayAs: date) else { return nil }
        return result
    }
}

public enum ScheduleValidationError: LocalizedError {
    case invalidData, invalidTime, limit, missingRule, occurrenceData
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "Saved schedules could not be read. The original data has been kept."
        case .invalidTime: return "Choose an hour from 0–23 and a minute from 0–59."
        case .limit: return "You can save up to 12 schedules. Delete one to make room."
        case .missingRule: return "This schedule no longer exists."
        case .occurrenceData: return "Schedule history could not be read. Schedules are paused to prevent duplicate changes. The original data has been kept."
        }
    }
}

public struct PresetScheduleLibrary: Codable, Equatable, Sendable {
    public let schema: Int
    public private(set) var schedules: [PresetSchedule]
    public init() { schema = 1; schedules = [] }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == 1, value.schedules.count <= 12,
              Set(value.schedules.map(\.id)).count == value.schedules.count,
              value.schedules.allSatisfy(\.isValid) else { throw ScheduleValidationError.invalidData }
        return value
    }

    public mutating func save(_ schedule: PresetSchedule, replacing: Bool = false) throws {
        guard schedule.isValid else { throw ScheduleValidationError.invalidTime }
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            guard replacing else { throw ScheduleValidationError.invalidData }
            schedules[index] = schedule
        } else {
            guard !replacing else { throw ScheduleValidationError.missingRule }
            guard schedules.count < 12 else { throw ScheduleValidationError.limit }
            schedules.append(schedule)
        }
    }
    public mutating func setEnabled(_ id: UUID, enabled: Bool) throws {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { throw ScheduleValidationError.missingRule }
        schedules[index].enabled = enabled
    }
    public mutating func delete(_ id: UUID) { schedules.removeAll { $0.id == id } }
}

/// A high-water civil date also prevents duplicate execution after the wall clock moves to an earlier day.
/// Gregorian date keys make calendar preference changes harmless; the user's timezone determines the day.
public struct PresetScheduleOccurrences: Codable, Equatable, Sendable {
    public let schema: Int
    public private(set) var handledDates: [String: String]
    public init() { schema = 1; handledDates = [:] }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = calendar.timeZone
        let parts = civil.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 131_072, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == 1, value.handledDates.count <= 1024,
              value.handledDates.allSatisfy({ key, day in UUID(uuidString: key)?.uuidString == key && validDay(day) }) else {
            throw ScheduleValidationError.occurrenceData
        }
        return value
    }
    public func hasHandled(_ id: UUID, on date: Date, calendar: Calendar) -> Bool {
        guard let previous = handledDates[id.uuidString] else { return false }
        return previous >= Self.dayKey(for: date, calendar: calendar)
    }
    public mutating func consume(_ id: UUID, on date: Date, calendar: Calendar) {
        let key = Self.dayKey(for: date, calendar: calendar)
        if key > (handledDates[id.uuidString] ?? "") { handledDates[id.uuidString] = key }
    }
    public mutating func retainSchedules(_ ids: Set<UUID>) {
        handledDates = handledDates.filter { key, _ in UUID(uuidString: key).map { ids.contains($0) } ?? false }
    }
    private static func validDay(_ day: String) -> Bool {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              day.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let number = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(number) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: number)
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }
}
