import Foundation

/// Bounds panel wake requests for one successful, app-owned disconnection.
/// Supply monotonic uptime and create a new budget for a new disconnection.
public struct PanelWakeBudget: Equatable, Sendable {
    public private(set) var attempts = 0
    public private(set) var isInFlight = false
    private var lastAttempt: TimeInterval?

    public init() {}

    /// Reserves one of two requests, with at least four seconds between starts.
    public mutating func begin(now: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, !isInFlight, attempts < 2 else { return false }
        if let lastAttempt {
            guard now >= lastAttempt, now - lastAttempt >= 4 else { return false }
        }
        attempts += 1
        isInFlight = true
        lastAttempt = now
        return true
    }

    /// A failed or timed-out request still consumes its attempt.
    public mutating func finish() {
        isInFlight = false
    }
}
