# Review, feature/everyday-controls, 2026-10-10

**Reviewed by**: Codex independent review agent
**Scope**: 7 implementation and test files, recording follow-up against `726d4bf`; production implementation `10e5390` plus the subsequent blur-observer regression assertions
**Verdict**: Approve

## Summary

The follow-up adds explicit keyboard recording to the existing shortcut editor and routes recorded bindings through the existing validated, conflict-safe Save path. Local AppKit events cover ordinary combinations, while the Carbon interception path captures already registered combinations without executing monitor actions. No actionable defect was found in the reviewed implementation.

## Strengths

- Recording requires both an open editor and a foreground app. Escape, explicit stop, app/window blur, editor disappearance, and application termination tear down the monitor and acceptance callback.
- Capture accepts only the existing supported physical keys and modifier combinations. It rejects unsupported keys, bare keys, and ordinary key-repeat events, while stripping unrelated AppKit flag bits.
- The monitor and notification observers are removed before accepting a binding, avoiding reentrant acceptance and accidental replacement of a captured draft.
- Recorder and registration state are MainActor-isolated; local monitor handling and main-queue notification handling explicitly enter that isolation.
- Carbon interception occurs after signature and live-registration validation and before any monitor action. Existing registrations remain in place, avoiding a new registration gap during recording.
- Capturing updates only the draft. Saving continues through duplicate/reserved-key validation, atomic registration updates, and persistence.

## Behavior clarified during review

Registered actions, including the keyboard recovery fallback, are deliberately suppressed throughout the foreground editor session, even when recording is stopped. This prevents a held registered key from changing a monitor after capture. The author confirmed this policy and documented it in AC-8 and the user guidance; panel recovery remains available, and global keyboard recovery resumes outside the foreground editor. This is broader than recording-only suppression.

## Test coverage

The reviewer independently ran the completed `StoreChecks` executable, including the added blur-observer assertions: all nine shortcut scenarios and five store orchestration scenarios passed. The recorder scenarios cover physical key/modifier capture, unsupported and unmodified input, repeats, Escape, repeated cleanup, attempts outside the editor or foreground app, ignored foreign signatures, registered-key capture, suppression after capture, recovery routing outside the foreground editor, and preservation of existing registrations. The added assertions install the actual local monitor and notification observers, post both AppKit blur notifications, verify cancellation, and verify that notifications after teardown no longer change recorder state.

The author reported native UI checks for recording/saving Control+Shift+K, capturing an already assigned combination, duplicate rejection, bare-key rejection and Escape draft preservation, capturing the reserved recovery combination and rejecting its assignment to another action, and stopping recording when the popover closes/reopens. The original binding was restored and monitor levels remained unchanged. Actual OS focus transitions remain unverified because the UI automation could not reliably activate another app; posting notifications proves observer plumbing, not WindowServer focus behavior. Physical global hotkey delivery also remains a native verification limit. This review did not run a concurrent build, install real hotkeys, or mutate physical monitors.
