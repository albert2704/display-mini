import Foundation
import IOKit.pwr_mgt

private final class FakeKeepAwakeBackend: KeepAwakeBackend {
    var nextID: IOPMAssertionID = 1
    var events: [String] = []
    var timeouts: [TimeInterval] = []
    var owned: Set<IOPMAssertionID> = []
    var createFails = false
    var releaseFails = false

    func create(timeout: TimeInterval) throws -> IOPMAssertionID {
        events.append("create")
        if createFails { throw KeepAwakeFailure(status: kIOReturnError) }
        let id = nextID
        nextID += 1
        timeouts.append(timeout)
        owned.insert(id)
        return id
    }

    func release(_ assertion: IOPMAssertionID) throws {
        events.append("release \(assertion)")
        if releaseFails { throw KeepAwakeFailure(status: kIOReturnError) }
        owned.remove(assertion)
    }
}

enum KeepAwakeTests {
    @MainActor static func run() {
        backendProperties()
        startStopAndReplacement()
        expiryAndLifecycle()
        failuresAndOwnership()
        print("Passed 4 Keep Displays Awake scenarios (OS timeout properties, ownership, expiry and lifecycle, operation failures).")
    }

    static func backendProperties() {
        let properties = IOKitKeepAwakeBackend.properties(timeout: 900)
        precondition(properties[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep)
        precondition(properties[kIOPMAssertionLevelKey] as? Int == kIOPMAssertionLevelOn)
        precondition(properties[kIOPMAssertionTimeoutKey] as? Double == 900)
        precondition(properties[kIOPMAssertionTimeoutActionKey] as? String == kIOPMAssertionTimeoutActionRelease)
        precondition((properties[kIOPMAssertionNameKey] as? String)?.contains("Display Mini") == true)
    }

    @MainActor static func startStopAndReplacement() {
        let backend = FakeKeepAwakeBackend()
        let controller = KeepAwakeController(backend: backend, now: { 100 }, startTimer: false)
        precondition(!controller.isActive && controller.remainingSeconds == 0 && backend.events.isEmpty, "Off at launch")
        precondition(controller.start(minutes: 15))
        precondition(controller.isActive && controller.remainingSeconds == 900 && backend.owned == [1])
        precondition(controller.remainingLabel == "15:00 remaining")
        precondition(controller.start(minutes: 60))
        precondition(backend.events == ["create", "release 1", "create"])
        precondition(backend.owned == [2] && backend.timeouts == [900, 3600])
        precondition(controller.remainingSeconds == 3600)
        precondition(!controller.start(minutes: 0) && controller.isActive && backend.owned == [2])
        precondition(controller.errorMessage != nil)
        controller.stop()
        controller.stop()
        precondition(backend.events == ["create", "release 1", "create", "release 2"])
        precondition(!controller.isActive && controller.remainingSeconds == 0 && backend.owned.isEmpty)
        precondition(controller.errorMessage == nil)
    }

    @MainActor static func expiryAndLifecycle() {
        let backend = FakeKeepAwakeBackend()
        var uptime: TimeInterval = 100
        let controller = KeepAwakeController(backend: backend, now: { uptime }, startTimer: false)
        precondition(controller.start(minutes: 30))
        uptime += 1799.1
        controller.evaluate()
        precondition(controller.isActive && controller.remainingSeconds == 1)
        uptime += 0.9
        controller.evaluate()
        controller.evaluate()
        precondition(!controller.isActive && backend.events == ["create", "release 1"])
        precondition(controller.start(minutes: 15))
        controller.suspend()
        precondition(!controller.isActive && backend.owned.isEmpty)
        controller.evaluate()
        precondition(!controller.isActive, "A sleep does not resume the old session")
        precondition(controller.start(minutes: 15))
        controller.shutdown()
        controller.shutdown()
        precondition(!controller.isActive && backend.owned.isEmpty && !controller.start(minutes: 15))
        precondition(backend.events.filter { $0.hasPrefix("release") }.count == 3)
    }

    @MainActor static func failuresAndOwnership() {
        let backend = FakeKeepAwakeBackend()
        var uptime: TimeInterval = 100
        var controller: KeepAwakeController? = KeepAwakeController(backend: backend, now: { uptime }, startTimer: false)
        backend.createFails = true
        precondition(!controller!.start(minutes: 15))
        precondition(!controller!.isActive && controller!.remainingSeconds == 0 && controller!.errorMessage != nil)
        backend.createFails = false
        precondition(controller!.start(minutes: 15))
        backend.releaseFails = true
        precondition(!controller!.start(minutes: 60))
        precondition(backend.timeouts == [900] && backend.owned == [1], "Failed release must not create a second assertion")
        precondition(controller!.isActive && controller!.errorMessage?.contains("Stop") == true)
        controller!.stop()
        precondition(controller!.isActive && backend.owned == [1])
        backend.releaseFails = false
        controller!.stop()
        precondition(!controller!.isActive && backend.owned.isEmpty)
        precondition(controller!.start(minutes: 15))
        backend.createFails = true
        precondition(!controller!.start(minutes: 30))
        precondition(!controller!.isActive && backend.owned.isEmpty, "Failed replacement does not claim an active session")
        backend.createFails = false
        precondition(controller!.start(minutes: 15))
        uptime += 900
        backend.owned.removeAll() // Simulate the OS having already released the expired ID.
        backend.releaseFails = true
        controller!.evaluate()
        precondition(!controller!.isActive && controller!.errorMessage == nil)
        backend.releaseFails = false
        precondition(controller!.start(minutes: 15))
        controller = nil
        precondition(backend.owned.isEmpty, "Destroying the controller releases its owned assertion")
    }
}
