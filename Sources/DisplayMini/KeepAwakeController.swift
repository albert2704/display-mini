import Foundation
import Combine
import IOKit.pwr_mgt

protocol KeepAwakeBackend: AnyObject {
    func create(timeout: TimeInterval) throws -> IOPMAssertionID
    func release(_ assertion: IOPMAssertionID) throws
}

struct KeepAwakeFailure: LocalizedError {
    let status: IOReturn
    var errorDescription: String? { "macOS power management returned error \(status)." }
}

final class IOKitKeepAwakeBackend: KeepAwakeBackend {
    // The OS timeout is independent of the app's timer, including if the app hangs.
    static func properties(timeout: TimeInterval) -> [String: Any] {
        [kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleDisplaySleep,
         kIOPMAssertionNameKey: "Display Mini: Keep Displays Awake",
         kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
         kIOPMAssertionTimeoutKey: timeout,
         kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease]
    }

    func create(timeout: TimeInterval) throws -> IOPMAssertionID {
        var assertion = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithProperties(Self.properties(timeout: timeout) as CFDictionary, &assertion)
        guard status == kIOReturnSuccess else { throw KeepAwakeFailure(status: status) }
        return assertion
    }

    func release(_ assertion: IOPMAssertionID) throws {
        let status = IOPMAssertionRelease(assertion)
        // The OS may have released it already when its timeout fired.
        guard status == kIOReturnSuccess || status == kIOReturnNotFound else { throw KeepAwakeFailure(status: status) }
    }
}

@MainActor final class KeepAwakeController: ObservableObject {
    static let durations = [15, 30, 60]
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var errorMessage: String?

    private struct Session { let assertion: IOPMAssertionID; let deadline: TimeInterval }
    private let backend: KeepAwakeBackend
    private let now: () -> TimeInterval
    private let startTimer: Bool
    private var session: Session?
    private var timer: Timer?
    private var isShutdown = false

    init(backend: KeepAwakeBackend? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         startTimer: Bool = true) {
        self.backend = backend ?? IOKitKeepAwakeBackend()
        self.now = now
        self.startTimer = startTimer
    }

    deinit {
        timer?.invalidate()
        if let session { try? backend.release(session.assertion) }
    }

    var remainingLabel: String {
        String(format: "%d:%02d remaining", remainingSeconds / 60, remainingSeconds % 60)
    }

    @discardableResult func start(minutes: Int) -> Bool {
        guard !isShutdown else { return false }
        guard Self.durations.contains(minutes) else {
            errorMessage = "Choose a 15, 30 or 60 minute session."
            return false
        }
        // Never create a replacement if releasing the previous assertion failed.
        guard endSession() else { return false }
        let duration = TimeInterval(minutes * 60)
        do {
            let assertion = try backend.create(timeout: duration)
            session = Session(assertion: assertion, deadline: now() + duration)
            isActive = true
            remainingSeconds = Int(duration)
            errorMessage = nil
            if startTimer {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.evaluate() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            return true
        } catch {
            errorMessage = "Could not keep displays awake. \(error.localizedDescription) Try again."
            return false
        }
    }

    func stop() { _ = endSession() }
    func suspend() { stop() }

    func shutdown() {
        isShutdown = true
        stop()
        timer?.invalidate()
        timer = nil
    }

    /// Tests inject uptime and call this directly, without a run loop or real power assertions.
    func evaluate() {
        guard let session else { return }
        let remaining = session.deadline - now()
        if remaining <= 0 { _ = endSession() }
        else { remainingSeconds = Int(ceil(remaining)) }
    }

    @discardableResult private func endSession() -> Bool {
        guard let session else { errorMessage = nil; return true }
        do {
            try backend.release(session.assertion)
        } catch {
            // Before the deadline, preserve ownership so Stop can retry and a replacement cannot leak it.
            guard now() >= session.deadline else {
                errorMessage = "Could not stop Keep Displays Awake. \(error.localizedDescription) Try Stop again; the automatic timeout is still in place."
                return false
            }
            // TimeoutActionRelease also releases in the OS. A late app timer can therefore see a stale ID.
        }
        timer?.invalidate()
        timer = nil
        self.session = nil
        isActive = false
        remainingSeconds = 0
        errorMessage = nil
        return true
    }
}
