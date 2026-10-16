import DisplayCore

enum ExplicitRecoveryTests {
    static func run() {
        let panel = DisplayConnectionState(uuid: "panel", builtIn: true, online: false, active: false)
        let external = DisplayConnectionState(uuid: "external", builtIn: false, online: true, active: true)
        func candidates(_ states: [DisplayConnectionState] = [panel, external],
                        owned: Set<String> = ["panel"], explicit: Set<String> = ["panel"],
                        lid: Bool? = false, sleeping: Bool = false, busy: Bool = false) -> [String] {
            BuiltInDisplayRecovery.candidates(states, owned: owned, lidClosed: lid,
                sleeping: sleeping, connectionBusy: busy, explicitlyRequested: explicit)
        }

        precondition(candidates(explicit: []).isEmpty,
                     "Automatic recovery preserves the chosen external-only layout")
        precondition(candidates() == ["panel"],
                     "An explicit reconnect remains eligible while an external screen is active")
        precondition(candidates(owned: []).isEmpty)
        precondition(candidates(owned: ["external"]).isEmpty)
        precondition(candidates(lid: true).isEmpty)
        precondition(candidates(lid: nil).isEmpty)
        precondition(candidates(sleeping: true).isEmpty)
        precondition(candidates(busy: true).isEmpty)
        let activePanel = DisplayConnectionState(uuid: "panel", builtIn: true, online: true, active: true)
        precondition(candidates([activePanel, external]).isEmpty)
        let startingPanel = DisplayConnectionState(uuid: "panel", builtIn: true, online: true, active: false)
        precondition(candidates([startingPanel, external]) == ["panel"])

        let otherPanel = DisplayConnectionState(uuid: "other", builtIn: true, online: false, active: false)
        precondition(candidates([panel, otherPanel, external], owned: ["panel", "other"]) == ["panel"],
                     "Explicit intent bypasses external presence only for the requested panel")
        let missingExternal = DisplayConnectionState(uuid: "external", builtIn: false, online: false, active: false)
        precondition(candidates([missingExternal], owned: ["external"], explicit: ["external"]).isEmpty)
        precondition(candidates(explicit: ["external"]).isEmpty)
        precondition(candidates([panel], explicit: []) == ["panel"],
                     "Ordinary unplug recovery remains available without explicit intent")
        print("Passed explicit recovery checks (active external, target scope, ownership, lid, sleep, busy and activation guards).")
    }
}
