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
        print("Passed 6 control tests (\(checks) assertions).")
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
