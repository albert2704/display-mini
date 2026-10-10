# Review, feature/everyday-controls, 2026-10-10

**Reviewed by**: Codex review agent (independent reviewer; model identifiers not exposed)
**Scope**: 11 files, requested editable-shortcut delta against `430efd8`; reviewed through `e5b9ca1`
**Verdict**: Approve

## Summary

The requested change makes all nine actions configurable and persists validated key/modifier bindings while retaining the fixed recovery fallback. Registration changes preserve existing keys until replacement keys are acquired; failed edits clean up staged registrations and leave the prior preferences intact. No actionable correctness finding remains in the reviewed delta.

## Strengths

- Atomic edits distinguish newly requested bindings from unrelated startup conflicts, so an unavailable action does not prevent the user from repairing another binding.
- Registration is keyed by chord, allowing reset to reuse an existing chord without unregistering and reacquiring it. Removed registration IDs and foreign event signatures cannot dispatch an action.
- Disabling everyday keys leaves the customized Restore binding and the fixed recovery fallback registered. Edits while disabled persist for the next enable.
- Persistence validates the schema, supported actions and key codes, modifier bits, uniqueness, and reserved recovery binding. Failed registration edits do not persist; unreadable data is retained and backed up on explicit recovery.
- Preset labels and missing-preset feedback read the current bindings. The editor clearly states the physical US key-position behavior and modifier requirement.

## Test coverage

The reviewer independently ran the updated `StoreChecks` executable successfully. All five shortcut scenarios and all five existing store scenarios passed. Shortcut checks cover preference validation and round trips, failed-edit cleanup after a partially successful staging attempt, action reassignment during reset, ignored obsolete/foreign events, disabled-mode recovery, unrelated startup conflicts, failed-save persistence, relaunch, defaults reset, and unreadable-data backup.

Actual Carbon acquisition/event delivery and native editor layout remain native verification surfaces being checked by the author. This review used source inspection and the injected registrar/store checks; it did not register real hotkeys or change physical monitor settings.
