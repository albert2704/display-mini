# 0003. Everyday controls

**Date**: 2026-10-10
**Status**: In Progress

## Summary and decision

Add monitor mute, named brightness/volume presets and global shortcuts to the existing native panel. The user selected these features and explicitly chose the screen under the pointer as the shortcut target. Continue the SwiftUI, Carbon and validated DDC architecture, with no new dependencies or permissions.

## Requirements

* AC-1: External displays with confirmed volume support offer mute and unmute. Muting writes zero through the existing verified DDC path. Unmuting restores the last confirmed nonzero volume for that display, including after relaunch; if none is known, use 25%. Failed writes roll back the UI and do not overwrite the remembered volume.
* AC-2: Save, rename, apply and delete up to 12 named presets. Capture settled brightness and supported volume for all connected screens. Names are trimmed, unique without regard to case, and 1–40 characters. Presets persist locally across relaunch.
* AC-3: Apply only to exact saved display UUID matches. Skip missing screens and unavailable volume controls, leave new screens untouched, and report partial failure or no matches. Never change connection, resolution or control method. Completion means writes have finished, not merely queued.
* AC-4: Ctrl+Option+Command with Up/Down changes brightness by five percentage points, Left/Right changes monitor volume, M toggles mute, and 1/2/3 applies the corresponding saved preset. Brightness, volume and mute target the screen under the pointer with no fallback to a different screen. Unsupported or busy targets produce visible feedback.
* AC-5: Everyday shortcuts can be disabled in a settings popover, persisted across launches. Show the mapping and registration conflicts. Ctrl+Option+Command+R remains independently registered for Restore Displays. Validate event signature and ID and clean up Carbon registrations.
* AC-6: Block conflicting control/configuration edits during preset application. Cancel pending batch work on restore, shutdown, sleep or display topology changes, ignoring stale completions. Restore Displays remains available. Preserve built-in unplug recovery.

## Feature design

Keep the 300-point material panel and existing `PanelStyle` tokens. Add a mute button beside the external volume slider and Presets and Shortcuts buttons in the footer. Presets opens a scrollable popover with an empty state, name field, Save Current action, saved rows with apply/rename/delete, busy state and result messages. Shortcut settings lists all bindings, an enabled switch and any conflicts. Labels remain accessible.

`DisplayPreset` contains an ID, name and entries with display UUID, display name, normalized brightness and optional normalized volume. A schema-1 Codable collection in UserDefaults validates count, duplicate identities/names, bounded strings and finite fractions before accepting data. Invalid data is preserved and reported instead of overwritten silently. No identifiers are included in diagnostic reports or sent over a network.

Preset execution reuses the existing debounced write paths with completion callbacks. A batch token and pending step IDs account for completion exactly once. Failed writes keep the existing rollback behavior. A topology refresh cancels an active batch before re-reading controls. Settings and control edits are unavailable until completion; recovery interrupts it. A canceled write already sent to hardware may finish, so cancellation is reported as interrupted rather than rolled back.

| Value | Source |
| --- | --- |
| Saved levels | Settled `confirmedBrightness` and `confirmedVolume` from native/DDC reads or successful writes |
| Saved identity/title | Existing display UUID and localized name |
| Unmute level | Last confirmed positive volume in per-display UserDefaults; 25% fallback |
| Shortcut target | `NSEvent.mouseLocation` inside an `NSScreen.frame`, matched by `NSScreenNumber` |
| Shortcut level | Current target level plus/minus 0.05, clamped to 0…1 |
| Preset shortcut order | Saved list insertion order; deletion shifts following positions |
| Batch result | Confirmed completion of every planned control write, plus skipped controls |

## Build plan

1. Add mute state, button and restoration regression tests (AC-1).
2. Add validated preset models, persistence, cancellation-safe execution and popover, with malformed-data and batch regression tests (AC-2, AC-3, AC-6).
3. Add Carbon action dispatch, pointer targeting, settings and registration lifecycle checks (AC-4, AC-5).
4. Build and test, verify the native UI and persistence, update user/developer guides, and publish a reviewed PR. Keep separate working commits.

## Consequences

Mute controls monitor volume, not macOS output or applications. DDC support remains required for volume. Saved levels may be rounded to the monitor's hardware range. Presets do not connect absent screens. Fixed modifier shortcuts avoid global key interception and Accessibility permission; custom bindings and media keys are deferred.

## References

* [DisplayBuddy presets](https://displaybuddy.app/docs/presets): named display settings and shortcut activation.
* [DisplayBuddy shortcuts](https://displaybuddy.app/docs/keyboard-shortcuts): everyday control inspiration.
* [Apple Carbon Event Manager](https://developer.apple.com/documentation/applicationservices/carbon_event_manager): registered global hotkeys, also checked against the installed SDK headers.
