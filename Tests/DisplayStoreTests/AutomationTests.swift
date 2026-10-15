import Foundation
import DisplayCore

@MainActor enum AutomationTests {
    static func run() {
        consumptionBeforeStartAndCompletion()
        busyMissingAndSimultaneousRules()
        startupEditsSleepAndClockGaps()
        dateReversalAndRestart()
        timezoneAndDST()
        storageRecoveryAndCRUD()
        print("Passed 6 preset automation scenarios (consumption and completion, eligibility and ordering, missed times, replay protection, timezone/DST, storage and editing).")
    }

    @MainActor final class Fixture {
        let domain = "dev.albert.DisplayMini.automation-tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var now = date("2026-10-15T11:59:40Z")
        var calendar: Calendar
        var presets = [DisplayPreset(name: "Work", displays: [.init(uuid: UUID().uuidString, name: "Fake display", brightness: 0.5, volume: nil)])]
        var readiness: String?
        var accept = true
        var calls: [UUID] = []
        var onApply: (() -> Void)?
        lazy var controller = makeController()
        init() {
            defaults = UserDefaults(suiteName: domain)!
            calendar = Calendar(identifier: .gregorian); calendar.locale = Locale(identifier: "en_US")
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        func clean() { controller.shutdown(); defaults.removePersistentDomain(forName: domain) }
        func makeController() -> PresetAutomationController {
            PresetAutomationController(defaults: defaults, clock: { [unowned self] in self.now },
                                       calendar: { [unowned self] in self.calendar }, automaticTimers: false)
        }
        func start(_ target: PresetAutomationController? = nil) {
            (target ?? controller).start(presets: { [unowned self] in self.presets },
                                        canApply: { [unowned self] _ in self.readiness },
                                        apply: { [unowned self] preset in
                self.calls.append(preset.id); self.onApply?(); return self.accept
            })
        }
        @discardableResult func add(hour: Int = 12, minute: Int = 0, preset: UUID? = nil) -> UUID {
            precondition(controller.save(presetID: preset ?? presets[0].id, hour: hour, minute: minute, recurrence: .daily))
            let id = controller.library.schedules.last!.id
            precondition(!controller.library.schedules.last!.enabled)
            precondition(controller.setEnabled(id, enabled: true))
            return id
        }
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds); controller.evaluate() }
    }

    static func consumptionBeforeStartAndCompletion() {
        let f = Fixture(); defer { f.clean() }; f.start()
        let id = f.add()
        f.onApply = {
            let history = try! PresetScheduleOccurrences.decode(f.defaults.data(forKey: "presetScheduleOccurrences")!)
            precondition(history.hasHandled(id, on: f.now, calendar: f.calendar))
        }
        f.advance(25)
        precondition(f.calls.count == 1 && f.controller.statuses[id]?.hasPrefix("Started") == true)
        f.advance(10); precondition(f.calls.count == 1)
        f.controller.completeActivePreset(message: "Applied Work.", succeeded: true)
        precondition(f.controller.statuses[id] == "Applied Work.")
        f.controller.completeActivePreset(message: "Unrelated manual preset", succeeded: true)
        precondition(f.controller.statuses[id] == "Applied Work.")
    }

    static func busyMissingAndSimultaneousRules() {
        let f = Fixture(); defer { f.clean() }; f.start()
        let missing = f.add()
        let removedID = f.presets.removeFirst().id
        f.presets = [.init(name: "Evening", displays: [])]
        let winner = f.add(), simultaneous = f.add()
        f.onApply = {
            let history = try! PresetScheduleOccurrences.decode(f.defaults.data(forKey: "presetScheduleOccurrences")!)
            for id in [missing, winner, simultaneous] { precondition(history.hasHandled(id, on: f.now, calendar: f.calendar)) }
        }
        f.advance(25)
        precondition(f.calls == [f.presets[0].id] && !f.calls.contains(removedID))
        precondition(f.controller.statuses[missing]?.contains("deleted") == true)
        precondition(f.controller.statuses[simultaneous]?.contains("another schedule") == true)
        f.controller.completeActivePreset(message: "One monitor rejected the change.", succeeded: false)
        precondition(f.controller.statuses[winner]?.hasPrefix("Failed:") == true)

        let busy = Fixture(); defer { busy.clean() }; busy.start()
        let busyID = busy.add(); busy.readiness = "display controls are busy."
        busy.advance(25); precondition(busy.calls.isEmpty && busy.controller.statuses[busyID]?.contains("busy") == true)
        busy.readiness = nil; busy.advance(10); precondition(busy.calls.isEmpty, "Busy occurrences are not retried")

        let unavailable = Fixture(); defer { unavailable.clean() }; unavailable.start()
        let unavailableID = unavailable.add(); unavailable.readiness = "no matching connected display."
        unavailable.advance(25)
        precondition(unavailable.calls.isEmpty && unavailable.controller.statuses[unavailableID]?.contains("no matching") == true)

        let rejected = Fixture(); defer { rejected.clean() }; rejected.start()
        let rejectedID = rejected.add(); rejected.accept = false; rejected.advance(25)
        precondition(rejected.controller.statuses[rejectedID]?.contains("could not start") == true)
        rejected.accept = true; rejected.advance(15); precondition(rejected.calls.count == 1)
    }

    static func startupEditsSleepAndClockGaps() {
        let startup = Fixture(); defer { startup.clean() }; startup.start(); startup.add()
        startup.controller.shutdown(); startup.now = date("2026-10-15T12:00:30Z")
        let restarted = startup.makeController(); defer { restarted.shutdown() }; startup.start(restarted)
        startup.now.addTimeInterval(15); restarted.evaluate(); precondition(startup.calls.isEmpty)

        let edit = Fixture(); defer { edit.clean() }; edit.now = date("2026-10-15T12:00:30Z"); edit.start()
        edit.add(); edit.advance(15); precondition(edit.calls.isEmpty, "New rules must not run retroactively within the minute")
        let id = edit.controller.library.schedules[0].id
        precondition(edit.controller.save(id: id, presetID: edit.presets[0].id, hour: 12, minute: 1, recurrence: .daily))
        edit.advance(20); precondition(edit.calls.count == 1)
        edit.controller.completeActivePreset(message: "Done", succeeded: true)
        precondition(edit.controller.save(id: id, presetID: edit.presets[0].id, hour: 12, minute: 2, recurrence: .daily))
        precondition(edit.controller.setEnabled(id, enabled: false) && edit.controller.setEnabled(id, enabled: true))
        edit.advance(60); precondition(edit.calls.count == 1, "Editing and toggling must retain today's consumption")

        let sleep = Fixture(); defer { sleep.clean() }; sleep.start(); sleep.add()
        sleep.controller.suspend(); sleep.advance(40); precondition(sleep.calls.isEmpty)
        sleep.controller.resume(); sleep.advance(15); precondition(sleep.calls.isEmpty)

        let gap = Fixture(); defer { gap.clean() }; gap.start(); gap.add()
        gap.advance(91); precondition(gap.calls.isEmpty && gap.controller.message?.contains("Missed") == true)
        gap.advance(15); precondition(gap.calls.isEmpty)
        gap.controller.shutdown(); gap.now = date("2026-10-16T11:59:50Z"); gap.advance(15)
        precondition(gap.calls.isEmpty, "Shutdown stops manual evaluations too")
    }

    static func dateReversalAndRestart() {
        let f = Fixture(); defer { f.clean() }; f.start(); f.add(); f.advance(25)
        f.controller.completeActivePreset(message: "Done", succeeded: true)
        f.now = date("2026-10-16T11:59:50Z"); f.controller.evaluate(); f.advance(15)
        precondition(f.calls.count == 2)
        f.controller.completeActivePreset(message: "Done", succeeded: true)
        f.now = date("2026-10-15T11:59:50Z"); f.controller.evaluate(); f.advance(15)
        precondition(f.calls.count == 2, "A→B→A must not run A twice")
        f.controller.shutdown(); f.now = date("2026-10-16T11:59:50Z")
        let restored = f.makeController(); defer { restored.shutdown() }; f.start(restored)
        f.now.addTimeInterval(15); restored.evaluate(); precondition(f.calls.count == 2)
    }

    static func timezoneAndDST() {
        let zone = Fixture(); defer { zone.clean() }; zone.start(); zone.add()
        zone.calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        zone.advance(25); precondition(zone.calls.isEmpty && zone.controller.message?.contains("Local time") == true)

        let spring = Fixture(); defer { spring.clean() }
        spring.calendar.timeZone = TimeZone(identifier: "America/New_York")!
        spring.now = date("2026-03-08T01:59:45-05:00"); spring.start(); spring.add(hour: 2, minute: 0)
        spring.advance(30); precondition(spring.calls.isEmpty)

        let fall = Fixture(); defer { fall.clean() }
        fall.calendar.timeZone = TimeZone(identifier: "America/New_York")!
        fall.now = date("2026-11-01T01:29:45-04:00"); fall.start(); fall.add(hour: 1, minute: 30)
        fall.advance(30); precondition(fall.calls.count == 1)
        fall.controller.completeActivePreset(message: "Done", succeeded: true)
        fall.now = date("2026-11-01T01:29:45-05:00"); fall.controller.evaluate(); fall.advance(30)
        precondition(fall.calls.count == 1)
    }

    static func storageRecoveryAndCRUD() {
        let f = Fixture(); defer { f.clean() }
        let broken = Data("not json".utf8)
        f.defaults.set(broken, forKey: "presetSchedules")
        f.defaults.set("untouched", forKey: "otherSetting")
        f.start(); precondition(f.controller.storageError != nil)
        precondition(!f.controller.save(presetID: f.presets[0].id, hour: 12, minute: 0, recurrence: .daily))
        precondition(f.defaults.data(forKey: "presetSchedules") == broken)
        f.controller.resetUnreadableStorage()
        precondition(f.defaults.data(forKey: "presetSchedulesBackup") == broken)
        precondition(f.defaults.string(forKey: "otherSetting") == "untouched")
        let id = f.add()
        precondition(!f.controller.save(id: id, presetID: UUID(), hour: 1, minute: 0, recurrence: .daily))
        precondition(!f.controller.save(id: id, presetID: f.presets[0].id, hour: 24, minute: 0, recurrence: .daily))
        precondition(f.controller.library.schedules.count == 1 && f.controller.library.schedules[0].hour == 12)
        f.controller.shutdown()
        f.defaults.set(broken, forKey: "presetScheduleOccurrences")
        let corruptHistory = f.makeController(); defer { corruptHistory.shutdown() }; f.start(corruptHistory)
        precondition(corruptHistory.storageError != nil)
        f.now.addTimeInterval(25); corruptHistory.evaluate(); precondition(f.calls.isEmpty)
        precondition(f.defaults.data(forKey: "presetScheduleOccurrences") == broken)
        corruptHistory.resetUnreadableStorage()
        precondition(f.defaults.data(forKey: "presetScheduleOccurrencesBackup") == broken)
        precondition(corruptHistory.library.schedules.isEmpty)
        precondition(corruptHistory.save(presetID: f.presets[0].id, hour: 13, minute: 0, recurrence: .weekdays))
        let newID = corruptHistory.library.schedules[0].id
        precondition(corruptHistory.delete(newID) && corruptHistory.library.schedules.isEmpty)
        for key in ["presetSchedules", "presetScheduleOccurrences"] {
            f.defaults.removeObject(forKey: "presetSchedules"); f.defaults.removeObject(forKey: "presetScheduleOccurrences")
            f.defaults.set("wrong plist type", forKey: key)
            let wrongType = f.makeController(); precondition(wrongType.storageError != nil); wrongType.shutdown()
        }
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
