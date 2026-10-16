# 0007. Built in panel recovery

**Date**: 2026-10-16
**Status**: In Progress, physical unplug validation pending

## Summary

When an owned MacBook panel disappears from display discovery, request a wake through the exact kernel service captured before disconnecting it. Then repeat normal display discovery before changing the desktop layout. A power request alone does not establish that the screen recovered.

## Context

Physical tests show that unplug detection runs with the lid open, but SkyLight returns only a stale external display. Direct queries of the saved built in display ID also fail: no UUID, unknown built in flag, and invalid hardware identity. Retrying those queries cannot reach the panel in that state.

A local read only probe established that CoreDisplay's `IODisplayLocation` maps the online built in panel directly to the unique internal IOMobileFramebuffer service. Its registry entry ID identifies that kernel object until reboot. No ancestor search, manufacturer guess or framebuffer ID conversion is required on the tested Mac.

The user delegated implementation choices. This is a focused recovery change on the existing Swift and AppKit stack, with no UI redesign or new persistent settings. Implementation proceeds as one complete recovery path with automated failure tests and a separate physical acceptance check.

## Requirements

- **AC-1**: With the lid open and the built in panel disconnected by this process, removing the last external connection restores the panel without reconnecting the cable. This requires physical confirmation.
- **AC-2**: Capture only an exactly identified built in panel and its directly mapped, uniquely classified internal kernel service before a successful disconnect. Missing or ambiguous mappings disable this fallback.
- **AC-3**: Wake only that still registered kernel object. Never pass a cached or framebuffer ID to a layout transaction when normal display resolution fails.
- **AC-4**: Permit at most two wake requests per successful disconnection, at least four seconds apart. Run outside the UI thread, with a two second helper alarm and three second parent deadline. Retain ownership until online and active confirmation.
- **AC-5**: Sleep, shutdown, closed or unknown lid, lost ownership, and conflicting connection operations suppress new wake requests. A stale completion cannot start a layout change.
- **AC-6**: Record bounded local status flags without screen identifiers. Missing APIs, rejected requests and timeouts leave ordinary discovery retries available and do not claim success.

## Options considered

1. Keep retrying direct CoreGraphics identity. Physical evidence refutes availability of that identity in the failing state.
2. Wake the captured kernel panel, then repeat normal discovery. This adds a private API but addresses the missing lower layer while preserving layout identity checks.
3. Enable an old numeric display ID without live identity. This cannot establish that the ID still names the intended display, so it is rejected.

## Decision

Use option 2. Capture `CoreDisplay_DisplayCreateInfoDictionary` → `IODisplayLocation` → `IORegistryEntryCopyFromPath` only when the UUID matches and `CGDisplayIsBuiltin == 1`. Require IOMobileFramebuffer conformance, an exact `disp0` component in `IONameMatched`, and one matching internal service. Retain only its registry entry ID in memory after successful disable.

The existing app executable has a private `--wake-built-in-panel <registry-entry-id>` subprocess mode that exits before AppKit starts. It resolves that exact registered service, repeats classification and lid checks, opens IOMobileFramebuffer, and requests power value `1`. The opaque framebuffer reference ends with the helper process; no unverified release function is used.

## Rationale

The kernel target remains separate from the CoreGraphics layout target. This lets recovery attempt to make the panel discoverable without weakening the identity rules for reconnecting a screen. A subprocess bounds private driver calls and reference lifetime using the existing command runner.

## Feature design

| State or action | Source and behavior |
|---|---|
| Capture | Current exact CG UUID and built in flag, direct CoreDisplay registry mapping, unique internal service |
| Owned session | In memory UUID, registry entry ID, generation token and `PanelWakeBudget`; committed only after successful disable |
| Eligibility | Existing unplug policy, current ownership, open lid, awake store, no connection or wake in progress |
| Wake | Same executable, fixed power on operation, same registered service and fresh lid checks |
| Completion | Clears the busy slot, rejects stale store generations, schedules fresh discovery after a settling delay |
| Manual recovery | Retains explicit intent across wake and discovery even while an external screen remains active; finishes other synchronous restore operations before starting a helper |
| Confirmation | Normal UUID/hardware resolution plus online and active state; then releases ownership and capture |
| Exhaustion | No more power requests for that disconnection; normal discovery retries continue |
| Relaunch | No kernel capture is reconstructed; existing ordinary recovery remains available |

The helper uses no privilege escalation and cannot power a panel off. Its input is a kernel registry ID, never a CG display ID. No identifier or raw helper output is added to diagnostics. The retry budget uses monotonic process uptime.

Critical checks: invalid targets and arguments perform no power call (AC-2, AC-3); repeated ticks and failures exhaust a fixed budget (AC-4); store callbacks retain ownership and cannot continue after shutdown (AC-4, AC-5); helper process checks retain existing DDC error handling (AC-6); the user performs the unplug test (AC-1).

## Build plan

1. Implement exact capture and the bounded wake helper, AC-2, AC-3, AC-4.
2. Integrate asynchronous recovery, ownership confirmation and callback guards, AC-4, AC-5, AC-6.
3. Run model, store and subprocess checks; build and launch the app, AC-2 through AC-6.
4. Repeat physical cable removal with persistent diagnostics, AC-1. Keep the PR in draft until this passes.

## Consequences

This requires additional private macOS APIs and a direct internal service mapping. Unsupported mappings fail closed. Captures cannot survive an app restart. Kernel wake may still fail to reintroduce the display, so automated checks do not establish AC-1 and the implementation remains under physical validation.
