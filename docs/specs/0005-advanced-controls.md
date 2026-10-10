# 0005. Advanced display controls

**Date**: 2026-10-10
**Status**: In Progress

## Summary

Add a dedicated Advanced tab beside the existing Displays tab. It contains linked brightness, monitor contrast, input switching and a refresh rate picker. The user requested features inspired by Display Buddy and other display utilities, grouped away from everyday controls.

## Context and decision

Reuse SwiftUI, PanelStyle, the bundled DDC helper and the existing mode confirmation flow. No new dependency or permission is needed. Extending the helper is preferable to adding another monitor library because it already implements contrast (0x12) and input (0x60), verified display routing and bounded reads.

## Requirements

- **AC-1**: The 300 point panel opens on Displays and offers an accessible Advanced tab. Recovery and resolution confirmation remain visible on both tabs.
- **AC-2**: An external display can explicitly detect advanced controls. Contrast is enabled only after a valid continuous range is read. A committed edit writes the monitor's range, verifies readback and rolls back the displayed value on failure.
- **AC-3**: Input switching requires a valid input read, a common standard source choice and explicit confirmation. Describe the choices as common codes, not a detected port list. Never claim that a successful Set command confirms the visible input. Explain how to return with monitor buttons. Reject switching while a built-in panel disabled by this app remains off.
- **AC-4**: Linked brightness defaults off and persists locally. Enabling it changes no screen. Subsequent brightness edits through Display Mini use the same percentage for all ready connected screens. Busy screens are skipped with feedback. Presets, recovery, and external macOS brightness edits do not fan out.
- **AC-5**: Refresh rates come from current macOS modes, restricted to the current logical size and exact pixel dimensions. Preserve distinct fractional rates, deduplicate equivalents, label zero as Variable / system, and resolve the selected descriptor again before applying. Use the existing 15 second Keep/Revert flow.
- **AC-6**: Advanced operations respect sleep, connection, preset and resolution guards. Ignore stale callbacks after refresh, disconnect, restore or shutdown. Invalid probe data must not enable writes. Normal brightness/volume detection does not gain extra reads.

## Feature design

The segmented tab picker sits above the scroll area. Advanced starts with a compact linked brightness card, then one card per screen. Each card shows name, refresh rate, and external monitor hardware controls. Built-in screens explain that contrast/input live on external hardware. Loading, unsupported, error and disconnected states remain explicit.

| Value | Source |
| --- | --- |
| Name, connection, modes | Existing DisplayDevice, current CoreGraphics enumeration |
| Contrast percentage | Valid probe current / maximum, rounded for display; write rounds fraction × maximum |
| Input status | Standard VCP 0x60 positive current value; noncontinuous, so maximum may be zero. Current zero leaves input unavailable without suppressing contrast |
| Input choices | Fixed common MCCS codes: VGA 1, DVI 3/4, DisplayPort 15/16, HDMI 17/18; unknown current codes displayed in hex |
| Refresh choices | FavoriteResolution geometry and millihertz identity from current modes, without favorite persistence |
| Linked brightness | UserDefaults `linkedBrightnessEnabled`, false if absent; injected defaults for tests |
| Hardware outcome | Separate helper results for verified continuous writes and unverified input command delivery |

Add `probe-advanced` with schema 1, UUID, transport, service count, timing, contrast and input. Keep `probe` unchanged. Reuse independent probe status validation, but validate input as a noncontinuous value. Helper execution stays serialized and bounded. Detection occurs on request, and cached readings are invalidated on refresh or control configuration changes.

Store methods: `detectAdvancedControls`, `setContrast`, `switchInput`, `refreshRateModes`, `changeRefreshRate`, and persisted `linkedBrightnessEnabled`. A per-device advanced operation token invalidates old responses. Only one advanced operation runs per device, and regular writes/configuration are blocked during it. Input state becomes unknown after sending, without a blind retry or automatic fallback. If an interrupted write may have arrived, the next detection reads reality.

Security: no network calls, credentials or new permissions. Route by stable UUID and reject objects removed from the store. Diagnostic export includes capability statuses, never display names or UUIDs. Input commands are never issued from previews, detection, tab navigation or tests.

## Build plan

1. Add and test the advanced probe and input model, AC-2, AC-3, AC-6.
2. Add the guarded store operations, linked edits and refresh mode selection, AC-2 through AC-6.
3. Build the tab and native cards, AC-1 through AC-5.
4. Run regression tests, compile/sign, verify native navigation and detection, and update guides/screenshots, all criteria.

## Consequences

Support depends on monitor firmware and the cable or dock. Common input codes are not an advertised capability list, and some screens need vendor specific commands that remain outside this change. Matching percentages across displays is not luminance calibration. Input switching may end communication, so its result cannot be verified by the normal write/readback method. Hardware switching and contrasting writes are separately reported from mock tests.

## References

- [Display Buddy getting started](https://displaybuddy.app/docs/getting-started), simple and expanded controls.
- [Display Buddy](https://displaybuddy.app/), contrast, input and sync features.
- [BetterDisplay](https://github.com/waydabber/BetterDisplay), image controls, input switching and synchronization.
- `Vendor/sources/m1ddc.m`, existing contrast and input protocol support.
