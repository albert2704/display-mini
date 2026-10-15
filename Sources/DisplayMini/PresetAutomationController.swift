import Foundation
import Combine
import DisplayCore

@MainActor final class PresetAutomationController: ObservableObject {
    @Published private(set) var library = PresetScheduleLibrary()
    @Published private(set) var statuses: [UUID: String] = [:]
    @Published private(set) var storageError: String?
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let calendar: () -> Calendar
    private let automaticTimers: Bool
    private var occurrences = PresetScheduleOccurrences()
    private var timer: Timer?
    private var running = false
    private var suspended = false
    private var baseline: Date?
    private var calendarIdentity: String?
    private var eligibleAfter: [UUID: Date] = [:]
    private var activeScheduleID: UUID?
    private var presets: () -> [DisplayPreset] = { [] }
    private var canApply: (DisplayPreset) -> String? = { _ in "Display controls are unavailable." }
    private var apply: (DisplayPreset) -> Bool = { _ in false }

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent }, automaticTimers: Bool = true) {
        self.defaults = defaults; self.clock = clock; self.calendar = calendar; self.automaticTimers = automaticTimers
        do {
            if let object = defaults.object(forKey: "presetSchedules") {
                guard let data = object as? Data else { throw ScheduleValidationError.invalidData }
                library = try PresetScheduleLibrary.decode(data)
            }
            if let object = defaults.object(forKey: "presetScheduleOccurrences") {
                guard let data = object as? Data else { throw ScheduleValidationError.occurrenceData }
                occurrences = try PresetScheduleOccurrences.decode(data)
            }
        } catch { storageError = error.localizedDescription }
    }

    /// A nil readiness reason means the preset can start. The executor remains the sole hardware writer.
    func start(presets: @escaping () -> [DisplayPreset], canApply: @escaping (DisplayPreset) -> String?,
               apply: @escaping (DisplayPreset) -> Bool) {
        self.presets = presets; self.canApply = canApply; self.apply = apply
        running = true; suspended = false; resetBaseline()
        timer?.invalidate()
        guard automaticTimers else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func suspend() { suspended = true; baseline = nil }
    func resume() {
        guard running else { return }
        suspended = false; resetBaseline()
        message = "Schedules resumed. Missed times were skipped."
    }
    func shutdown() {
        timer?.invalidate(); timer = nil; running = false; baseline = nil
        presets = { [] }; canApply = { _ in "Display controls are unavailable." }; apply = { _ in false }
    }

    func evaluate() {
        guard running, !suspended, storageError == nil else { return }
        let now = clock(), currentCalendar = calendar()
        let identity = Self.identity(currentCalendar)
        guard let previous = baseline, calendarIdentity == identity else {
            baseline = now; calendarIdentity = identity
            message = "Local time settings changed. Missed times were skipped."
            return
        }
        baseline = now
        let elapsed = now.timeIntervalSince(previous)
        guard elapsed > 0, elapsed <= 90 else {
            if elapsed < 0 { message = "The clock moved backward. Schedule timing restarted." }
            if elapsed > 90 { message = "Schedules paused while the app was inactive. Missed times were skipped." }
            return
        }
        let days = currentCalendar.isDate(previous, inSameDayAs: now) ? [now] : [previous, now]
        var due: [(rule: PresetSchedule, time: Date)] = []
        for rule in library.schedules where rule.enabled {
            for day in days {
                guard let time = rule.occurrence(on: day, calendar: currentCalendar), time > previous, time <= now,
                      time > (eligibleAfter[rule.id] ?? .distantPast),
                      !occurrences.hasHandled(rule.id, on: time, calendar: currentCalendar) else { continue }
                due.append((rule, time))
            }
        }
        // Preserve editor order for simultaneous rules. No callback runs before every occurrence is consumed.
        due.sort { $0.time < $1.time || ($0.time == $1.time && index(of: $0.rule.id) < index(of: $1.rule.id)) }
        guard !due.isEmpty else { return }
        for item in due { occurrences.consume(item.rule.id, on: item.time, calendar: currentCalendar) }
        persistOccurrences()
        var started = false
        let available = presets()
        for item in due {
            let id = item.rule.id
            guard let preset = available.first(where: { $0.id == item.rule.presetID }) else {
                statuses[id] = "Skipped: preset was deleted."; continue
            }
            guard !started else { statuses[id] = "Skipped: another schedule started at this time."; continue }
            if let reason = canApply(preset) { statuses[id] = "Skipped: \(reason)"; continue }
            guard activeScheduleID == nil else { statuses[id] = "Skipped: another scheduled preset is still running."; continue }
            activeScheduleID = id; statuses[id] = "Started “\(preset.name)”."
            if apply(preset) { started = true }
            else {
                if activeScheduleID == id { activeScheduleID = nil }
                statuses[id] = "Skipped: the preset could not start."
            }
        }
    }

    func completeActivePreset(message: String, succeeded: Bool) {
        guard let id = activeScheduleID else { return }
        activeScheduleID = nil
        // A deleted schedule must not reappear when a pending hardware callback arrives.
        if library.schedules.contains(where: { $0.id == id }) {
            statuses[id] = succeeded ? message : "Failed: \(message)"
        }
    }

    @discardableResult func save(id: UUID? = nil, presetID: UUID, hour: Int, minute: Int,
                                recurrence: PresetScheduleRecurrence) -> Bool {
        guard storageError == nil else { return false }
        guard presets().contains(where: { $0.id == presetID }) else {
            message = "Choose an existing preset. Save one in Presets first."; return false
        }
        let existing = id.flatMap { id in library.schedules.first { $0.id == id } }
        let schedule = PresetSchedule(id: id ?? UUID(), presetID: presetID, hour: hour, minute: minute,
                                      recurrence: recurrence, enabled: existing?.enabled ?? false)
        return edit(id: schedule.id) { try $0.save(schedule, replacing: id != nil) }
    }
    @discardableResult func setEnabled(_ id: UUID, enabled: Bool) -> Bool {
        edit(id: id) { try $0.setEnabled(id, enabled: enabled) }
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        guard edit(id: id, { $0.delete(id) }) else { return false }
        occurrences.retainSchedules(Set(library.schedules.map(\.id))); persistOccurrences()
        eligibleAfter.removeValue(forKey: id); statuses.removeValue(forKey: id)
        return true
    }
    func resetUnreadableStorage() {
        guard storageError != nil else { return }
        for key in ["presetSchedules", "presetScheduleOccurrences"] {
            if let original = defaults.object(forKey: key) {
                let backup = defaults.object(forKey: key + "Backup") == nil ? key + "Backup" : key + "Backup." + UUID().uuidString
                defaults.set(original, forKey: backup)
            }
            defaults.removeObject(forKey: key)
        }
        library = PresetScheduleLibrary(); occurrences = PresetScheduleOccurrences()
        statuses = [:]; eligibleAfter = [:]; storageError = nil; resetBaseline()
        message = "Created an empty schedule library. The original data was backed up locally."
    }
    private func edit(id: UUID, _ edit: (inout PresetScheduleLibrary) throws -> Void) -> Bool {
        guard storageError == nil else { return false }
        do {
            var next = library; try edit(&next)
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: "presetSchedules"); library = next
            eligibleAfter[id] = clock(); message = nil
            if activeScheduleID != id { statuses.removeValue(forKey: id) }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func persistOccurrences() {
        // The model contains only UUIDs and validated dates, so encoding cannot fail.
        if let data = try? JSONEncoder().encode(occurrences) { defaults.set(data, forKey: "presetScheduleOccurrences") }
    }
    private func resetBaseline() { baseline = clock(); calendarIdentity = Self.identity(calendar()) }
    private static func identity(_ calendar: Calendar) -> String { "\(calendar.identifier)|\(calendar.timeZone.identifier)" }
    private func index(of id: UUID) -> Int { library.schedules.firstIndex { $0.id == id } ?? Int.max }
}
