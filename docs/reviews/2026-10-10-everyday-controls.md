# Review, feature/everyday-controls, 2026-10-10

**Reviewed by**: Codex review agent (independent reviewer; model identifiers not exposed)
**Scope**: 12 files, branch vs main at merge base `5a4cda4fe370c87445cd41ccb2a06e2869d258aa`, including the untracked shortcut source files and store tests
**Verdict**: Approve

## Summary

The change adds remembered monitor mute, validated named presets, serial preset execution, and registered global shortcuts targeting the pointer's screen. The author resolved the two integration defects identified during review: presenting the panel no longer cancels an active preset, and interrupted in-flight writes now trigger reconciliation before settled-control actions become available. The final reviewed code also blocks manual edits during reconciliation and reconciles successful recovery writes, with no remaining concrete correctness finding.

## Resolved during review

- `Sources/DisplayMini/AppMain.swift`: panel presentation skips its ordinary refresh while a preset is active, preserving progress inspection without interrupting the batch.
- `Sources/DisplayMini/DisplayStore.swift`: cancellation marks control state as needing a read; saving, mute, configuration, and manual control changes wait for reconciliation. Stale read/write callbacks drain correctly without completing an old batch, and successful recovery writes also trigger the deferred read.
- `Tests/DisplayStoreTests/StoreTests.swift`: tests now compile and execute the real store against hardware substitutes, exercising the asynchronous orchestration rather than only its value helpers. The configured runner includes this suite.

## Strengths

- Preset persistence validates schema, size, identities, display entries, finite ranges, names, and duplicates; unreadable data is preserved for explicit recovery.
- Preset steps run serially and have per-step IDs plus a batch token, preventing duplicate or stale completions from finishing a later batch.
- Carbon event handling validates the signature and action ID, checks that the action is still registered before dispatch, and unregisters on shutdown. Restore registration remains separate from the everyday toggle.
- Mute remembers only valid positive confirmed volumes, and normal successful writes update that memory after verification.
- The store tests cover sequential application with partial failure, interruption and late completion, failed unmute rollback, slow recovery-write reconciliation, and disabled/busy/missing-preset/no-pointer-target shortcut guards.

## Test coverage

The core tests meaningfully cover mute fallback, library limits/names/round trips, malformed payload rejection, missing or unsupported display planning, and duplicate/stale progress tokens. The added store suite covers actual state transitions and callback ordering with stubbed hardware; the reviewer independently ran the resulting `StoreChecks` executable successfully: all five scenarios passed. Existing helper-process and C protocol checks remain configured in `scripts/test.sh`.

This review performed source inspection and hardware-free checks. It did not independently repeat the author's native build, mutate physical monitors, or exercise actual Carbon event delivery, registration conflicts, native popover behavior, or live pointer targeting. Those remain native verification surfaces rather than claims made by this code review.
