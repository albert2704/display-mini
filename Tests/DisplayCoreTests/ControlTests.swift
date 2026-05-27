import Foundation
import DisplayCore

private var checks = 0
private func XCTAssertTrue(_ value: Bool, _ detail: String = "", file: StaticString = #filePath, line: UInt = #line) {
    precondition(value, "Assertion failed: \(detail)", file: (file), line: line); checks += 1
}
private func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(!value, file: file, line: line) }
private func XCTAssertNil<T>(_ value: T?, _ detail: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value == nil, detail, file: file, line: line) }
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a == b, "\(a) != \(b)", file: file, line: line) }
private func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(abs(a - b) <= accuracy, "\(a) != \(b)", file: file, line: line) }
private func XCTAssertGreaterThan(_ a: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a > b, file: file, line: line) }

@main struct ControlTests {
    static func main() {
        let suite = ControlTests()
        suite.testDDCRejectsFailuresRatherThanPresentingThemAsZero()
        suite.testDDCScalesToReportedMaximumAndClampsInputs()
        suite.testCombinedBrightnessHasContinuousBoundaryAndRoundTripsHardwareReadings()
        suite.testLastDisplayCannotBeDisconnected()
        suite.testResolutionSliderPreservesCurrentDensityAndRefresh()
        suite.testDisconnectedDisplayIdentitySurvivesLossOfUUIDAndChangeOfID()
        suite.testStructuredProbeRejectsWrongIdentityAndUnsafeRanges()
        suite.testProbeDistinguishesUnsupportedFromCommunicationFailure()
        suite.testTimingAndDiagnosticReportPrivacy()
        suite.testUnverifiedAndAmbiguousRoutesNeverEnableControls()
        suite.testUnplugRestoresOnlyTheOwnedBuiltInPanel()
        suite.testUnplugRecoveryRespectsLidSleepAndTransactions()
        suite.testHardwareUnplugOverridesStaleWindowServerState()
        suite.testHardwareLinkEventsRejectUnknownAndRespectNewestState()
        suite.testMuteRestoresOnlyConfirmedValidVolume()
        suite.testPresetPersistenceAndNames()
        suite.testPresetDataRejectsCorruption()
        suite.testPresetPlanSkipsMissingAndUnsupportedControls()
        suite.testPresetProgressRejectsDuplicateAndStaleCallbacks()
        PersonalizationTests.run()
        print("Passed 19 control tests (\(checks) assertions).")
    }

    private var presetDisplay: PresetDisplay {
        .init(uuid: fixtureUUID, name: "Synthetic monitor", brightness: 0.7, volume: 0.4)
    }
    func testPresetPersistenceAndNames() {
        var library = PresetLibrary()
        try! library.save(name: "  Work  ", displays: [presetDisplay])
        XCTAssertEqual(library.presets.first?.name, "Work")
        XCTAssertTrue((try? library.save(name: "work", displays: [presetDisplay])) == nil)
        for name in ["", "   ", "bad\nname", String(repeating: "a", count: 41)] {
            XCTAssertTrue((try? library.save(name: name, displays: [presetDisplay])) == nil)
        }
        try! library.rename(id: library.presets[0].id, name: "Evening")
        let restored = try! PresetLibrary.decode(JSONEncoder().encode(library))
        XCTAssertEqual(restored, library)
        for index in 1...11 { try! library.save(name: "Preset \(index)", displays: [presetDisplay]) }
        XCTAssertTrue((try? library.save(name: "Overflow", displays: [presetDisplay])) == nil)
        library.delete(id: library.presets[0].id)
        XCTAssertEqual(library.presets.count, 11)
        XCTAssertEqual(library.presets[0].name, "Preset 1")
    }
    func testPresetDataRejectsCorruption() {
        var library = PresetLibrary()
        for displays in [[], [presetDisplay, presetDisplay],
                         [.init(uuid: "invalid", name: "Bad", brightness: 0.5, volume: nil)],
                         [.init(uuid: fixtureUUID, name: "Bad", brightness: .nan, volume: nil)],
                         [.init(uuid: fixtureUUID, name: "Bad", brightness: 0.5, volume: 2)]] {
            XCTAssertTrue((try? library.save(name: "Invalid", displays: displays)) == nil)
        }
        XCTAssertNil(try? PresetLibrary.decode(Data("{".utf8)))
        XCTAssertNil(try? PresetLibrary.decode(Data("{\"schema\":2,\"presets\":[]}".utf8)))
        try! library.save(name: "Work", displays: [presetDisplay])
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as! [String: Any]
        let presets = json["presets"] as! [[String: Any]]
        json["presets"] = presets + presets
        XCTAssertNil(try? PresetLibrary.decode(JSONSerialization.data(withJSONObject: json)))
        var preset = presets[0]; preset["name"] = "  untrimmed  "
        json["presets"] = [preset]
        XCTAssertNil(try? PresetLibrary.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testPresetPlanSkipsMissingAndUnsupportedControls() {
        let second = PresetDisplay(uuid: "00000000-0000-4000-8000-000000000002", name: "Other", brightness: 0.9, volume: 0.3)
        let preset = DisplayPreset(name: "Work", displays: [presetDisplay, second])
        let plan = PresetPlan(preset: preset, available: [fixtureUUID: false, "new-screen": true])
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].displayUUID, fixtureUUID)
        XCTAssertEqual(plan.steps[0].control.rawValue, "brightness")
        XCTAssertEqual(plan.steps[0].value, 0.7)
        XCTAssertEqual(plan.skippedControls, 3)
        XCTAssertTrue(PresetPlan(preset: preset, available: [:]).steps.isEmpty)
        let full = PresetPlan(preset: preset, available: [fixtureUUID: true, second.uuid: true])
        XCTAssertEqual(full.steps.count, 4)
        XCTAssertEqual(full.skippedControls, 0)
    }
    func testPresetProgressRejectsDuplicateAndStaleCallbacks() {
        let plan = PresetPlan(preset: .init(name: "Work", displays: [presetDisplay]), available: [fixtureUUID: true])
        var progress = PresetProgress(steps: plan.steps)
        XCTAssertFalse(progress.finish(token: UUID(), step: plan.steps[0].id, success: false))
        XCTAssertEqual(progress.pending.count, 2)
        XCTAssertTrue(progress.finish(token: progress.token, step: plan.steps[0].id, success: false))
        XCTAssertFalse(progress.finish(token: progress.token, step: plan.steps[0].id, success: false))
        XCTAssertEqual(progress.failures, 1)
        XCTAssertTrue(progress.finish(token: progress.token, step: plan.steps[1].id, success: true))
        XCTAssertTrue(progress.pending.isEmpty)
        var next = PresetProgress(steps: plan.steps)
        XCTAssertFalse(next.finish(token: progress.token, step: plan.steps[0].id, success: true))
        XCTAssertEqual(next.pending.count, 2)
    }

    func testMuteRestoresOnlyConfirmedValidVolume() {
        XCTAssertEqual(MonitorAudio.toggledVolume(current: 0.8, remembered: nil), 0)
        XCTAssertEqual(MonitorAudio.toggledVolume(current: 0, remembered: 0.8), 0.8)
        XCTAssertEqual(MonitorAudio.rememberedVolume(confirmed: 0, previous: 0.8), 0.8)
        XCTAssertEqual(MonitorAudio.rememberedVolume(confirmed: 0.4, previous: 0.8), 0.4)
        // A failed write does not produce a confirmed value, so the last good level survives.
        XCTAssertEqual(MonitorAudio.rememberedVolume(confirmed: nil, previous: 0.8), 0.8)
        for invalid in [Double.nan, Double.infinity, -1, 0, 1.1] {
            XCTAssertEqual(MonitorAudio.toggledVolume(current: 0, remembered: invalid), 0.25)
        }
        XCTAssertEqual(MonitorAudio.toggledVolume(current: 0, remembered: nil), 0.25)
    }

    func testHardwareUnplugOverridesStaleWindowServerState() {
        let panel = DisplayConnectionState(uuid: "panel", builtIn: true, online: false, active: false)
        let staleMonitor = DisplayConnectionState(uuid: "monitor", builtIn: false, online: true, active: true)
        let states = [panel, staleMonitor]
        XCTAssertTrue(BuiltInDisplayRecovery.candidates(states, owned: ["panel"], lidClosed: false,
            sleeping: false, connectionBusy: false).isEmpty)
        XCTAssertEqual(BuiltInDisplayRecovery.candidates(states, owned: ["panel"], lidClosed: false,
            sleeping: false, connectionBusy: false, physicalExternalLost: true), ["panel"])
        XCTAssertTrue(BuiltInDisplayRecovery.candidates(states, owned: ["panel"], lidClosed: true,
            sleeping: false, connectionBusy: false, physicalExternalLost: true).isEmpty)
        XCTAssertTrue(BuiltInDisplayRecovery.candidates(states, owned: [], lidClosed: false,
            sleeping: false, connectionBusy: false, physicalExternalLost: true).isEmpty)
    }

    func testHardwareLinkEventsRejectUnknownAndRespectNewestState() {
        func event(_ payload: [String: Any]) -> [String: Any] { ["EventPayload": payload] }
        let staleHints: [String: Any] = ["MaxW": 2560, "MaxH": 1440]
        XCTAssertNil(ExternalLinkState.active(hints: nil, events: []))
        XCTAssertNil(ExternalLinkState.active(hints: nil, events: [event(["State": "Registered", "Value": 1])]))
        XCTAssertNil(ExternalLinkState.active(hints: nil, events: [event(["Action": "Unrecognized"])]))
        XCTAssertEqual(ExternalLinkState.active(hints: staleHints, events: []), true)
        XCTAssertEqual(ExternalLinkState.active(hints: ["Valid": false], events: []), false)
        XCTAssertEqual(ExternalLinkState.active(hints: staleHints,
            events: [event(["Action": "Plug"]), event(["Action": "Unplug"])]), false)
        XCTAssertEqual(ExternalLinkState.active(hints: nil,
            events: [event(["Action": "Unplug"]), event(["Action": "Plug"])]), true)
        XCTAssertEqual(ExternalLinkState.active(hints: staleHints,
            events: [event(["State": "SinkActive", "Value": 0])]), false)
        XCTAssertEqual(ExternalLinkState.active(hints: nil,
            events: [event(["State": "SinkActive", "Value": 1])]), true)
        XCTAssertNil(ExternalLinkState.active(hints: nil,
            events: [event(["State": "SinkActive", "Value": "bad"])]))
    }

    func testUnplugRestoresOnlyTheOwnedBuiltInPanel() {
        let panel = DisplayConnectionState(uuid: "panel", builtIn: true, online: false, active: false)
        let monitor = DisplayConnectionState(uuid: "monitor", builtIn: false, online: true, active: true)
        let secondMonitor = DisplayConnectionState(uuid: "second", builtIn: false, online: true, active: true)
        let owned: Set<String> = ["panel", "monitor"]
        func candidates(_ states: [DisplayConnectionState], owned: Set<String> = owned) -> [String] {
            BuiltInDisplayRecovery.candidates(states, owned: owned, lidClosed: false, sleeping: false, connectionBusy: false)
        }
        // The panel stays disabled while a replacement is available.
        XCTAssertTrue(candidates([panel, monitor, secondMonitor]).isEmpty)
        XCTAssertTrue(candidates([panel, secondMonitor]).isEmpty)
        // Unplugging the last external monitor must restore the panel.
        XCTAssertEqual(candidates([panel]), ["panel"])
        let offlineMonitor = DisplayConnectionState(uuid: "monitor", builtIn: false, online: false, active: false)
        XCTAssertEqual(candidates([panel, offlineMonitor]), ["panel"])
        XCTAssertTrue(candidates([panel], owned: ["monitor"]).isEmpty)
        XCTAssertTrue(candidates([panel], owned: []).isEmpty)
        // A stale active flag on an offline monitor must not prevent recovery.
        let removed = DisplayConnectionState(uuid: "monitor", builtIn: false, online: false, active: true)
        XCTAssertEqual(candidates([panel, removed]), ["panel"])
        // An enable request is not confirmation. Retry until both flags are true.
        let enabling = DisplayConnectionState(uuid: "panel", builtIn: true, online: true, active: false)
        XCTAssertEqual(candidates([enabling]), ["panel"])
        let restored = DisplayConnectionState(uuid: "panel", builtIn: true, online: true, active: true)
        XCTAssertTrue(candidates([restored]).isEmpty)
        XCTAssertTrue(candidates([restored], owned: ["monitor"]).isEmpty)
    }

    func testUnplugRecoveryRespectsLidSleepAndTransactions() {
        let panel = DisplayConnectionState(uuid: "panel", builtIn: true, online: false, active: false)
        for lidClosed: Bool? in [true, nil] {
            XCTAssertTrue(BuiltInDisplayRecovery.candidates([panel], owned: ["panel"], lidClosed: lidClosed,
                                                          sleeping: false, connectionBusy: false).isEmpty)
        }
        XCTAssertTrue(BuiltInDisplayRecovery.candidates([panel], owned: ["panel"], lidClosed: false,
                                                      sleeping: true, connectionBusy: false).isEmpty)
        XCTAssertTrue(BuiltInDisplayRecovery.candidates([panel], owned: ["panel"], lidClosed: false,
                                                      sleeping: false, connectionBusy: true).isEmpty)
        XCTAssertEqual(BuiltInDisplayRecovery.candidates([panel], owned: ["panel"], lidClosed: false,
                                                       sleeping: false, connectionBusy: false), ["panel"])
    }
    private var fixtureUUID: String { "00000000-0000-4000-8000-000000000001" }
    private var probeFixture: [String: Any] {
        ["schema": 1, "uuid": fixtureUUID, "transport": "mcdp", "serviceCount": 1, "delayMS": 50,
         "brightness": ["status": "ok", "attempts": 1, "current": 128, "maximum": 255],
         "volume": ["status": "unsupported", "attempts": 1]]
    }
    private func parse(_ fixture: [String: Any], uuid: String? = nil, timing: DDCTiming = .standard) -> DDCProbe? {
        DDCProbe.parse(try! JSONSerialization.data(withJSONObject: fixture), expectedUUID: uuid ?? fixtureUUID, timing: timing)
    }
    func testStructuredProbeRejectsWrongIdentityAndUnsafeRanges() {
        XCTAssertEqual(parse(probeFixture)?.brightness.fraction ?? 0, 128.0 / 255, accuracy: 0.0001)
        XCTAssertNil(parse(probeFixture, uuid: "00000000-0000-4000-8000-000000000002"))
        XCTAssertNil(parse(probeFixture, uuid: "not-a-display-uuid"))
        for (current, maximum) in [(1, 0), (101, 100), (-1, 100), (0, 65536)] {
            var fixture = probeFixture
            fixture["brightness"] = ["status": "ok", "attempts": 1, "current": current, "maximum": maximum]
            XCTAssertNil(parse(fixture))
        }
        for (key, value) in [("schema", 2), ("serviceCount", 2), ("delayMS", 150)] {
            var fixture = probeFixture; fixture[key] = value
            XCTAssertNil(parse(fixture))
        }
        XCTAssertNil(DDCProbe.parse(Data("truncated {".utf8), expectedUUID: fixtureUUID, timing: .standard))
    }
    func testProbeDistinguishesUnsupportedFromCommunicationFailure() {
        for status in ["unsupported", "invalidReply", "invalidRange", "writeError", "readError"] {
            var fixture = probeFixture
            fixture["volume"] = ["status": status, "attempts": 3]
            let probe = parse(fixture)
            XCTAssertEqual(probe?.volume.status.rawValue, status)
            XCTAssertNil(probe?.volume.fraction)
            XCTAssertTrue(probe?.brightness.fraction != nil)
        }
        for attempts in [-1, 0, 4] {
            var fixture = probeFixture; fixture["volume"] = ["status": "ok", "attempts": attempts, "current": 50, "maximum": 100]
            XCTAssertNil(parse(fixture))
        }
        var fixture = probeFixture; fixture["volume"] = ["status": "invented", "attempts": 1]
        XCTAssertNil(parse(fixture))
    }
    func testTimingAndDiagnosticReportPrivacy() {
        XCTAssertEqual(DDCTiming(saved: nil), .standard)
        XCTAssertEqual(DDCTiming(saved: "unknown"), .standard)
        XCTAssertEqual(DDCTiming(saved: "slow").delayMS, 150)
        var fixture = probeFixture; fixture["delayMS"] = 150
        fixture["serial"] = "SYNTHETIC-PRIVATE-SERIAL"
        fixture["path"] = "/synthetic/private/path"
        fixture["name"] = "Private display name"
        let report = parse(fixture, timing: .slow)!.diagnosticLines.joined(separator: "\n")
        for secret in [fixtureUUID, "SYNTHETIC-PRIVATE-SERIAL", "/synthetic/private/path", "Private display name"] {
            XCTAssertFalse(report.contains(secret))
        }
        XCTAssertTrue(report.contains("150 ms"))
        XCTAssertTrue(report.contains("128/255"))
    }
    func testUnverifiedAndAmbiguousRoutesNeverEnableControls() {
        for route in ["none", "ambiguous"] {
            var fixture = probeFixture
            fixture["transport"] = route; fixture["serviceCount"] = 0
            fixture["brightness"] = ["status": "notAvailable", "attempts": 0]
            fixture["volume"] = ["status": "notAvailable", "attempts": 0]
            XCTAssertTrue(parse(fixture) != nil)
            XCTAssertNil(parse(fixture)?.brightness.fraction)
            fixture["brightness"] = ["status": "ok", "attempts": 1, "current": 50, "maximum": 100]
            XCTAssertNil(parse(fixture))
        }
    }
    func testDDCRejectsFailuresRatherThanPresentingThemAsZero() {
        for value in ["-1", "DDC communication failure: timeout", "", "50\n100", "65536", "nan"] {
            XCTAssertNil(ControlMath.parseDDC(value), value)
        }
        XCTAssertEqual(ControlMath.parseDDC("  75\n"), 75)
        XCTAssertEqual(ControlMath.parseDDC("0"), 0)
    }

    func testDDCScalesToReportedMaximumAndClampsInputs() {
        XCTAssertEqual(ControlMath.rawValue(fraction: 0.75, maximum: 255), 191)
        XCTAssertEqual(ControlMath.rawValue(fraction: -3, maximum: 100), 0)
        XCTAssertEqual(ControlMath.rawValue(fraction: 3, maximum: 100), 100)
        XCTAssertEqual(ControlMath.rawValue(fraction: .nan, maximum: 100), 100)
    }

    func testCombinedBrightnessHasContinuousBoundaryAndRoundTripsHardwareReadings() {
        XCTAssertEqual(ControlMath.combined(0.2).hardware, 0, accuracy: 0.0001)
        XCTAssertEqual(ControlMath.combined(0.2).software, 1, accuracy: 0.0001)
        XCTAssertEqual(ControlMath.combined(0.1).software, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(ControlMath.combined(0).software, 0)
        for hardware in [0.0, 0.1, 0.5, 1.0] {
            XCTAssertEqual(ControlMath.combined(ControlMath.combinedValue(hardware: hardware)).hardware, hardware, accuracy: 0.0001)
        }
    }

    func testLastDisplayCannotBeDisconnected() {
        XCTAssertFalse(ControlMath.mayDisconnect(isEnabled: true, activeCount: 1, pending: false))
        XCTAssertFalse(ControlMath.mayDisconnect(isEnabled: true, activeCount: 0, pending: false))
        XCTAssertTrue(ControlMath.mayDisconnect(isEnabled: true, activeCount: 2, pending: false))
        XCTAssertTrue(ControlMath.mayDisconnect(isEnabled: false, activeCount: 0, pending: false))
        XCTAssertFalse(ControlMath.mayDisconnect(isEnabled: false, activeCount: 2, pending: true))
    }

    func testResolutionSliderPreservesCurrentDensityAndRefresh() {
        let current = ModeDescriptor(id: 1, width: 1728, height: 1117, pixelWidth: 3456, refresh: 120)
        let choices = [current,
                       ModeDescriptor(id: 2, width: 1728, height: 1117, pixelWidth: 1728, refresh: 60),
                       ModeDescriptor(id: 3, width: 1440, height: 900, pixelWidth: 2880, refresh: 60),
                       ModeDescriptor(id: 4, width: 1440, height: 900, pixelWidth: 2880, refresh: 120),
                       ModeDescriptor(id: 5, width: 1440, height: 900, pixelWidth: 1440, refresh: 120)]
        XCTAssertEqual(ModeSelection.sliderModes(choices, current: current).map(\.id), [4, 1])
        XCTAssertTrue(ModeSelection.sliderModes([], current: nil).isEmpty)
    }

    func testDisconnectedDisplayIdentitySurvivesLossOfUUIDAndChangeOfID() {
        // Synthetic serials: regression fixtures must not identify a real device.
        let lg = DisplayIdentity(displayID: 3, vendor: 7789, model: 23491, serial: 100001)
        let builtIn = DisplayIdentity(displayID: 1, vendor: 1552, model: 41041, serial: 100002)
        let emptySlot = DisplayIdentity(displayID: 2, vendor: 0, model: 0, serial: 0)
        let changedID = DisplayIdentity(displayID: 7, vendor: 7789, model: 23491, serial: 100001)
        XCTAssertEqual(DisplayIdentity.resolve(lg, among: [builtIn, emptySlot, lg]), 3)
        XCTAssertEqual(DisplayIdentity.resolve(lg, among: [builtIn, emptySlot, changedID]), 7)
        XCTAssertNil(DisplayIdentity.resolve(lg, among: [builtIn, emptySlot]))
        XCTAssertNil(DisplayIdentity.resolve(emptySlot, among: [emptySlot]))
        XCTAssertNil(DisplayIdentity.resolve(lg, among: [lg, changedID]))
    }
}
