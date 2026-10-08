# 0002. Monitor compatibility and diagnostics

**Date**: 2026-10-09
**Status**: In Progress

## Summary

Improve external monitor discovery, offer a slower DDC response profile, and explain each control's communication result. Keep the existing compact panel and open the extra detail from Monitor Controls.

## Context and rationale

The user selected compatibility and connection diagnostics, then requested inspiration from BetterDisplay and DisplayBuddy. BetterDisplay's configurable DDC timing and DisplayBuddy's visible control modes fit this scope. Current discovery stops at four online displays, relies on registry traversal order, and launches separate reads for current and maximum values. One failing control overwrites the other control's explanation.

Keep the native Swift/SwiftUI and vendored Objective-C helper. A broader manual service matcher or Wi-Fi smart monitor integration would require hardware identification and protocol work outside this update. Ambiguous routes must fail visibly rather than select another screen.

## Requirements

* AC-1: Discover up to 64 online displays, check enumeration failure, initialize missing metadata safely, and reject invalid or ambiguous selectors.
* AC-2: Match external DDC services using their own EDID vendor/model/serial and the selected display's CoreGraphics identity. Validate the EDID base block. Reject duplicate online identities and multiple matches. Preserve the existing MCDP29xx address handling.
* AC-3: One structured read probe returns current and maximum from the same reply for brightness and volume independently. Validate reply checksum, command, feature, support status and numeric range. Validate the returned display UUID before accepting readings.
* AC-4: Persist Standard (50 ms read wait) or Slow (150 ms) per display. Keep three bounded read attempts and a process deadline. A settings change retries reads, never sends a Set VCP command. Existing writes use the selected timing for confirmation.
* AC-5: Show route, per-control outcome, attempts, raw range, last check time, and actionable help in Monitor Controls. Missing control replies are not described as confirmed lack of support.
* AC-6: Copy a diagnostic report on explicit button click. Include app/OS version, vendor/model codes, connection and mode, profile, route and probe results. Exclude UUIDs, serials, display names, registry paths, local paths, and raw helper output. Nothing is uploaded.
* AC-7: Drain subprocess output with a size limit while it runs; report missing helper, timeout, oversized or malformed output, and failed command distinctly. Preserve existing brightness/volume rollback and connection recovery behavior.

## Feature design

The helper adds `--delay-ms 50|150 display <uuid> probe`. JSON schema 1 includes internal UUID, transport (`standard`, `mcdp`, `none`, `ambiguous`), candidate count, read delay, and brightness/volume objects. Each object contains status, attempts and optional current/maximum/error code. Status is one of `ok`, `unsupported`, `invalidReply`, `invalidRange`, `writeError`, `readError`, `notAvailable`. Only `ok` with a valid positive maximum produces a controllable value.

Swift stores the latest decoded probe and check date on each display record. Failures clear the latest probe rather than displaying old results as current. Profile preference uses `ddcTiming.<uuid>` in UserDefaults; invalid saved values fall back to Standard. Configuration is disabled during reads, writes, pending edits or display configuration. A probe completion must still match the display revision and online state.

| UI value | Source |
| --- | --- |
| Display title, connected state, resolution | Existing display record and CoreGraphics |
| Native/software/DDC brightness mode | Existing successful native read, validated DDC result, software preference |
| Route and service count | Helper service EDID matched against the selected CoreGraphics identity |
| Current/max and attempts | One validated VCP reply and bounded attempt counter |
| Last check | Completion time of the most recent accepted probe |
| Response timing | Per-display UserDefaults preference, 50 or 150 ms |
| Troubleshooting text | Fixed explanations keyed by probe or process failure category |
| Copy report | Explicitly selected safe fields; never a dump of helper JSON |

The Monitor Controls popover uses the existing material, fonts, spacing and blue accent. It contains control mode, response timing, a connection status section, per-control result rows, Detect Again and Copy Report. Long content scrolls. Loading and failed results remain readable; controls unavailable during work explain their status.

## Build plan

1. Extend discovery and helper probe, AC-1 through AC-3.
2. Add typed validation, bounded process runner and profile persistence, AC-3, AC-4, AC-7.
3. Add diagnostics UI and safe report, AC-5 and AC-6.
4. Test protocol classification, malformed/wrong-display JSON, profile selection, report privacy, timeout and excessive output. Build and perform read-only live probes and UI inspection. Update guides and feature research notes.

## Consequences

Slow mode takes longer and may help delayed replies; it cannot make a dock forward DDC. Reads remain required before hardware controls are enabled. Write-only monitors, DisplayLink, Intel DDC, arbitrary VCP mappings and smart TV network control are not added. No claim of broad hardware certification follows from simulated tests or one LG monitor.

Live inspection showed that the LG's AppleCLCD2 framebuffer and DCP service are in separate registry branches. A descendant-only matcher would break this connection. `IOAVServiceCopyEDID` provided independently matching vendor/model/serial values. Use that positive match rather than registry traversal order. If the API, EDID, or unique identity is unavailable, report no verified route. Identical monitors reporting identical identities remain a documented limitation.

## References

* [BetterDisplay DDC settings](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/ddc/): bounded timing settings and communication options.
* [DisplayBuddy Getting Started](https://displaybuddy.app/docs/getting-started): per-display control modes and simple/expanded UI.
* [DisplayBuddy troubleshooting](https://displaybuddy.app/troubleshooting): DDC/CI settings, picture modes and connection paths.
* [m1ddc source](https://github.com/waydabber/m1ddc): existing vendored transport; retain its MIT license.
* [IOAVService API research](https://gist.github.com/zhuowei/223e449a90a32eefd2c3244e252818d1): signature of the dynamically resolved EDID read API.
