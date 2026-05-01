# 0001. Native display controls

**Date**: 2026-10-08
**Status**: Implemented for the 0.1.0 preview; physical hardware validation remains partial.

This records the initial design. See [Architecture](../ARCHITECTURE.md) and [Development](../DEVELOPMENT.md) for the current implementation and validation limits. The release uses direct compiler scripts; `Package.swift` is provided for project structure and optional SwiftPM use.

## Summary

Display Mini is a native macOS menu bar utility for the controls in the supplied BetterDisplay screenshot. It controls brightness, resolution, external monitor volume, and connection state. It runs independently of BetterDisplay.

## Context

The target is the user's Apple Silicon Mac and its built in display and LG IPS QHD monitor. The user asked to replicate BetterDisplay's behavior, including its connection switches. No existing project or context file governs this new directory. This is a local personal app, built in complete slices.

## Requirements

* **AC-1**: List real attached displays with their names and current values in a compact native menu bar panel matching the screenshot.
* **AC-2**: Brightness adjusts the built in display through DisplayServices and supported external displays through DDC. Combine hardware brightness with software dimming below the hardware minimum. Unsupported hardware uses clearly labelled software dimming.
* **AC-3**: External monitor volume uses DDC VCP 0x62, reflects read values, and explains unsupported connections. A configuration panel can retry DDC or explicitly select software brightness.
* **AC-4**: Resolution choices come from CoreGraphics. Apply on release, offer Keep or Revert, and revert automatically after 15 seconds. Show HiDPI and refresh rate in the picker.
* **AC-5**: Switches disconnect and reconnect through SkyLight. Never disconnect the last active display. Retain disconnected displays in the panel. Restore owned disconnections on quit, on next launch after a crash, and through Control Option Command R.
* **AC-6**: Handle hotplug, wake, missing private APIs, failed reads and writes, and long DDC calls without freezing the panel or falsely claiming success. Package a launchable app with its helper and licenses.

## Options considered

Native Swift and AppKit provide the smallest direct integration with macOS displays. A web wrapper would still require a native helper and add a runtime. Driving BetterDisplay's CLI would be quick but would not provide an independent alternative.

## Decision

Use SwiftUI inside an AppKit status item popover, Swift Package Manager, CoreGraphics, dynamically resolved DisplayServices and SkyLight, and the MIT m1ddc executable built from vendored source. No account, network service, telemetry, or runtime downloads. No new installable skills or MCP services are needed.

## Rationale

Native controls fit the supplied design and accessibility conventions. A separate monitor helper gives DDC calls a timeout boundary. Private APIs are necessary for the requested brightness and connection behavior; unavailable symbols must disable the affected action with an explanation.

## Feature design

The in memory display record contains CoreGraphics ID, stable display UUID, hardware vendor/model/serial identity, name, built in flag, connection state, brightness, volume, supported modes, current mode, transport capability, and last error. Optional values remain unknown until successfully read. UserDefaults holds per UUID software preference, software dimming level, known hardware identities, UUIDs disconnected by this app, and the previous resolution during a pending preview. Recovery can therefore survive an app crash. macOS drops the UUID of a disconnected display; reconnection resolves the saved hardware identity against the current private display list and rejects ambiguous matches. Restore also lifts displays in the lower software dimming range to readable brightness.

| Action | Inputs | Value source and result |
|---|---|---|
| Refresh | OS screen event or refresh button | NSScreen names; CoreGraphics/SkyLight list, UUID, modes, active state; DisplayServices and DDC readbacks |
| Brightness | UUID, fraction 0 through 1 | Combine a lower 20% software range with hardware 0 through 100%; pure software fallback uses screen overlay opacity |
| Volume | UUID, fraction 0 through 1 | DDC current and maximum VCP 0x62 values; no invented measured value |
| Resolution | UUID, CoreGraphics mode | Enumerated native mode, with logical and physical dimensions and refresh rate; previous mode for rollback |
| Connection | UUID, enabled Bool | Fresh ID from SkyLight; transactional configure; active display count guard |
| Recover | No inputs | Reconnect only UUIDs this app disconnected; remove dimming overlays; rollback pending mode |

DDC operations run on a serial background queue, use a bundled absolute helper path, bounded timeout, and UUID selection. Slider writes are debounced and stale reads cannot overwrite an active edit. A failed hardware write keeps the last confirmed value and shows an error. Connection state is verified from the OS. No elevated privileges or Accessibility permission is needed. No destructive monitor commands are used.

The design source is the user screenshot: translucent material, rounded display title rows, small labels, blue switches, white brightness and resolution sliders, and a compact DDC configuration affordance. Footer includes only refresh, restore, and quit.

Critical verification: parser rejects invalid DDC output; scaling respects monitor maxima; mode grouping retains current mode and correct refresh/density; last screen guard; resolution rollback; actual application launch and accessibility tree; read hardware values without changing the user's display setup during automated verification.

## Build plan

1. Implement real discovery and readback, AC-1 and AC-6.
2. Implement brightness, volume, DDC configuration, AC-2 and AC-3.
3. Implement resolution transactions, connection transactions, and recovery, AC-4 and AC-5.
4. Build the compact native panel and packaged app, AC-1 and AC-6.
5. Verify meaningful logic tests, build, application launch, and read only hardware probe, AC-1 through AC-6.

## Consequences

The app requires macOS 14 or later on Apple Silicon. DDC depends on monitor firmware, DDC/CI settings and the cable or adapter. Private APIs may change with macOS. The preview is ad hoc signed; smooth public installation requires Developer ID signing and notarization. Hardware mutation tests require observing the physical screens and are reported separately from automated checks.
