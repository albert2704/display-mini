import DisplayCore

enum PanelWakeBudgetTests {
    static func run() {
        var budget = PanelWakeBudget()
        precondition(budget.attempts == 0 && !budget.isInFlight)
        precondition(budget.begin(now: 10))
        precondition(budget.attempts == 1 && budget.isInFlight)

        // Even a delayed helper must not overlap a second request.
        precondition(!budget.begin(now: 20))
        precondition(budget.attempts == 1 && budget.isInFlight)
        budget.finish()
        precondition(budget.attempts == 1 && !budget.isInFlight)

        // Failed attempts retain their start time; rejected calls do not move it.
        precondition(!budget.begin(now: 9))
        precondition(!budget.begin(now: 10))
        precondition(!budget.begin(now: 13.999))
        precondition(budget.attempts == 1 && !budget.isInFlight)
        precondition(budget.begin(now: 14))
        precondition(budget.attempts == 2 && budget.isInFlight)
        budget.finish()
        budget.finish()
        precondition(!budget.begin(now: 18))
        precondition(!budget.begin(now: 1_000_000))
        precondition(budget.attempts == 2 && !budget.isInFlight)

        // Finishing an idle budget cannot spend or replenish an attempt.
        var fresh = PanelWakeBudget()
        fresh.finish()
        precondition(fresh.attempts == 0 && fresh.begin(now: 0))
        fresh.finish()
        precondition(fresh.begin(now: 4))

        // Invalid clock values must leave the complete budget unchanged.
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            var unused = PanelWakeBudget()
            let original = unused
            precondition(!unused.begin(now: invalid) && unused == original)
            precondition(unused.begin(now: 0))
            let running = unused
            precondition(!unused.begin(now: invalid) && unused == running)
            unused.finish()
            let finished = unused
            precondition(!unused.begin(now: invalid) && unused == finished)
            precondition(unused.begin(now: 4))
        }

        // Avoid a lastAttempt + interval comparison that can round away the gap.
        var largeUptime = PanelWakeBudget()
        precondition(largeUptime.begin(now: Double.greatestFiniteMagnitude))
        largeUptime.finish()
        precondition(!largeUptime.begin(now: Double.greatestFiniteMagnitude))
        precondition(!largeUptime.begin(now: .infinity))
        precondition(largeUptime.attempts == 1 && !largeUptime.isInFlight)
        print("Passed panel wake budget checks (single flight, spacing, exhaustion, fresh disconnect and invalid clocks).")
    }
}
