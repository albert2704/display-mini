import Foundation
import DisplayCore

enum ScheduleTests {
    static func run() {
        libraryValidationAndLimits()
        recurrenceAndStrictDST()
        dailyHighWaterAndCorruption()
        print("Passed 3 schedule model scenarios (validation and limits, recurrence and DST, daily history and corruption).")
    }

    static func libraryValidationAndLimits() {
        var library = PresetScheduleLibrary()
        let rule = PresetSchedule(presetID: UUID(), hour: 8, minute: 5)
        precondition(!rule.enabled && rule.timeTitle == "08:05")
        try! library.save(rule)
        precondition(try! PresetScheduleLibrary.decode(JSONEncoder().encode(library)) == library)
        precondition((try? library.save(rule)) == nil)
        var changed = rule; changed.minute = 59; changed.enabled = true
        try! library.save(changed, replacing: true)
        precondition(library.schedules == [changed])
        try! library.setEnabled(rule.id, enabled: false)
        precondition(!library.schedules[0].enabled)
        for _ in 1..<12 { try! library.save(.init(presetID: UUID(), hour: 0, minute: 0)) }
        precondition((try? library.save(.init(presetID: UUID(), hour: 0, minute: 0))) == nil)
        precondition((try? library.save(.init(presetID: UUID(), hour: 0, minute: 0), replacing: true)) == nil)
        library.delete(rule.id)
        precondition(library.schedules.count == 11)
        let encoded = try! JSONEncoder().encode(library)
        var object = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let rules = object["schedules"] as! [[String: Any]]
        for (key, invalid) in [("hour", -1), ("hour", 24), ("minute", -1), ("minute", 60)] {
            var badRule = rules[0]; badRule[key] = invalid
            object["schedules"] = [badRule]
            precondition((try? PresetScheduleLibrary.decode(JSONSerialization.data(withJSONObject: object))) == nil)
        }
        object["schedules"] = [rules[0], rules[0]]
        precondition((try? PresetScheduleLibrary.decode(JSONSerialization.data(withJSONObject: object))) == nil)
        object["schedules"] = rules; object["schema"] = 2
        precondition((try? PresetScheduleLibrary.decode(JSONSerialization.data(withJSONObject: object))) == nil)
        for malformed in ["{", "{}", "{\"schema\":1,\"schedules\":[{\"id\":\"bad\"}]}"] {
            precondition((try? PresetScheduleLibrary.decode(Data(malformed.utf8))) == nil)
        }
        precondition((try? PresetScheduleLibrary.decode(Data(repeating: 0, count: 65_537))) == nil)
    }

    static func recurrenceAndStrictDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = date("2026-03-08T12:00:00-04:00")
        let missing = PresetSchedule(presetID: UUID(), hour: 2, minute: 30)
        precondition(missing.occurrence(on: spring, calendar: calendar) == nil)
        let regular = PresetSchedule(presetID: UUID(), hour: 3, minute: 30)
        precondition(regular.occurrence(on: spring, calendar: calendar) == date("2026-03-08T03:30:00-04:00"))
        let repeated = PresetSchedule(presetID: UUID(), hour: 1, minute: 30)
        precondition(repeated.occurrence(on: date("2026-11-01T12:00:00-05:00"), calendar: calendar) == date("2026-11-01T01:30:00-04:00"))
        let weekday = PresetSchedule(presetID: UUID(), hour: 9, minute: 0, recurrence: .weekdays)
        let weekend = PresetSchedule(presetID: UUID(), hour: 9, minute: 0, recurrence: .weekends)
        precondition(weekday.occurrence(on: spring, calendar: calendar) == nil)
        precondition(weekend.occurrence(on: spring, calendar: calendar) != nil)
        let monday = date("2026-03-09T12:00:00-04:00")
        precondition(weekday.occurrence(on: monday, calendar: calendar) != nil)
        precondition(weekend.occurrence(on: monday, calendar: calendar) == nil)
        let midnight = PresetSchedule(presetID: UUID(), hour: 0, minute: 0)
        precondition(midnight.occurrence(on: monday, calendar: calendar) == calendar.startOfDay(for: monday))
    }

    static func dailyHighWaterAndCorruption() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 25_200)!
        let first = date("2026-10-15T23:59:00+07:00"), second = date("2026-10-16T00:01:00+07:00")
        let id = UUID(), other = UUID()
        var history = PresetScheduleOccurrences()
        precondition(!history.hasHandled(id, on: first, calendar: calendar))
        history.consume(id, on: first, calendar: calendar)
        precondition(history.hasHandled(id, on: first, calendar: calendar))
        precondition(!history.hasHandled(id, on: second, calendar: calendar))
        history.consume(id, on: second, calendar: calendar)
        precondition(history.hasHandled(id, on: first, calendar: calendar), "A→B→A cannot replay the first date")
        precondition(!history.hasHandled(other, on: first, calendar: calendar))
        precondition(try! PresetScheduleOccurrences.decode(JSONEncoder().encode(history)) == history)
        for day in ["2026-02-30", "2025-02-29", "2026-13-01", "2026-00-01", "0000-01-01", "2026-1-01", "nonsense"] {
            let object: [String: Any] = ["schema": 1, "handledDates": [id.uuidString: day]]
            precondition((try? PresetScheduleOccurrences.decode(JSONSerialization.data(withJSONObject: object))) == nil)
        }
        for object: [String: Any] in [
            ["schema": 2, "handledDates": [:]], ["schema": 1, "handledDates": ["invalid": "2026-10-15"]],
            ["schema": 1, "handledDates": [id.uuidString.lowercased(): "2026-10-15"]]
        ] { precondition((try? PresetScheduleOccurrences.decode(JSONSerialization.data(withJSONObject: object))) == nil) }
        history.retainSchedules([other]); precondition(history.handledDates.isEmpty)
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
