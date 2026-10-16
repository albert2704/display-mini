# 0007. Built in panel recovery

**Date**: 2026-10-16
**Status**: In Progress, physical unplug validation pending

## Summary

When an owned MacBook panel disappears from display discovery, request a wake through the exact kernel service captured before disconnecting it. If discovery still fails, reconnect the CG display ID captured with that same kernel object during this app session, provided there is no evidence of ID reuse. Neither request alone establishes that the screen recovered.

## Context

Physical tests show that unplug detection runs with the lid open, but SkyLight returns only a stale external display. Direct queries of the saved built in display ID also fail: no UUID, unknown built in flag, and invalid hardware identity. Retrying those queries cannot reach the panel in that state.

A local read only probe established that CoreDisplay's `IODisplayLocation` maps the online built in panel directly to the unique internal IOMobileFramebuffer service. Its registry entry ID identifies that kernel object until reboot. No ancestor search, manufacturer guess or framebuffer ID conversion is required on the tested Mac.

The next physical test accepted both kernel wake requests but still omitted the panel from CG discovery. Wake alone therefore does not restore desktop membership. Apple describes CG display IDs as typically stable until reboot, and BetterDisplay records retaining disconnected IDs through the app session until reuse. The recovery target now pairs the captured CG ID with its still registered kernel service and treats any readable identity contradiction as a permanent veto.

A normal disconnect check also proved that CoreDisplay's `kCGDisplayUUID` differs from the saved CG UUID while the hardware identity and registry mapping remain the same. The fallback therefore compares CoreDisplay's registry location only, never conflating those two UUID values.

The user delegated implementation choices. This is a focused recovery change on the existing Swift and AppKit stack, with no UI redesign or new persistent settings. Implementation proceeds as one complete recovery path with automated failure tests and a separate physical acceptance check.

## Requirements

- **AC-1**: With the lid open and the built in panel disconnected by this process, removing the last external connection restores the panel without reconnecting the cable. This requires physical confirmation.
- **AC-2**: Capture only an exactly identified built in panel and its directly mapped, uniquely classified internal kernel service before a successful disconnect. Missing or ambiguous mappings disable this fallback.
- **AC-3**: Wake only that still registered kernel object. If normal resolution fails, permit a captured CG ID only after an accepted wake, with continued ownership, the same kernel service, absence from private/online/active lists, and no readable identity conflict. Permanently discard a capture if another identity is observed using its ID. Never use an IOMobileFramebuffer ID as a CG ID.
- **AC-4**: Permit at most two wake requests per successful disconnection, at least four seconds apart. Run outside the UI thread, with a two second helper alarm and three second parent deadline. Retain ownership until online and active confirmation.
- **AC-5**: Sleep, shutdown, closed or unknown lid, lost ownership, and conflicting connection operations suppress new wake requests. A stale completion cannot start a layout change.
- **AC-6**: Record bounded local status flags without screen identifiers. Missing APIs, rejected requests and timeouts leave ordinary discovery retries available and do not claim success.

## Options considered

1. Keep retrying direct CoreGraphics identity. Physical evidence refutes availability of that identity in the failing state.
2. Wake the captured kernel panel, then require normal discovery. Physical testing showed both wake requests accepted but no panel reappearance, so this alone is insufficient.
3. Wake the panel, then use its session CG ID backed by the captured kernel service and reuse guards. This addresses absent discovery while constraining the target to one owned internal panel.

## Decision

Use option 3. Capture `CoreDisplay_DisplayCreateInfoDictionary` → `IODisplayLocation` → `IORegistryEntryCopyFromPath` only when the UUID matches and `CGDisplayIsBuiltin == 1`. Require IOMobileFramebuffer conformance, an exact `disp0` component in `IONameMatched`, and one matching internal service. Retain the registry entry ID, CG ID, UUID and valid hardware identity in memory after successful disable.

The existing app executable has a private `--wake-built-in-panel <registry-entry-id>` subprocess mode that exits before AppKit starts. It resolves that exact registered service, repeats classification and lid checks, opens IOMobileFramebuffer, and requests power value `1`. The opaque framebuffer reference ends with the helper process; no unverified release function is used.

## Rationale

The captured CG target is tied to the same still registered kernel object. Missing CG metadata is expected in the failing state, while contradictory metadata remains a veto. Each accepted wake permits one captured layout attempt, at most twice per disconnection. A subprocess bounds private driver calls and reference lifetime using the existing command runner. This is a targeted recovery exception, never a general cache for brightness, resolution or disconnect operations.

## Feature design

| State or action | Source and behavior |
|---|---|
| Capture | Current exact CG UUID and built in flag, direct CoreDisplay registry mapping, unique internal service |
| Owned session | In memory UUID, registry entry ID, generation token and `PanelWakeBudget`; committed only after successful disable |
| Eligibility | Existing unplug policy, current ownership, open lid, awake store, no connection or wake in progress |
| Wake | Same executable, fixed power on operation, same registered service and fresh lid checks |
| Completion | Clears the busy slot, rejects stale store generations, schedules fresh discovery after a settling delay; accepted wake permits one guarded captured reconnect attempt |
| Captured reconnect | Normal lookup failed; captured ID absent from all three lists; same unique live kernel object; no current UUID, readable hardware, explicit external flag or CoreDisplay mapping contradiction |
| Manual recovery | Retains explicit intent across wake and discovery even while an external screen remains active; finishes other synchronous restore operations before starting a helper |
| Confirmation | Normal UUID/hardware resolution plus online and active state; then releases ownership and capture |
| Exhaustion | No more power requests for that disconnection; normal discovery retries continue |
| Relaunch | No kernel capture is reconstructed; existing ordinary recovery remains available |

The helper uses no privilege escalation and cannot power a panel off. Its input is a kernel registry ID, never a CG display ID. The separate layout fallback is enable only and never reconstructed after relaunch. No identifier or raw helper output is added to diagnostics. The retry budget uses monotonic process uptime.

Critical checks: invalid targets and arguments perform no power call (AC-2, AC-3); repeated ticks and failures exhaust a fixed budget (AC-4); store callbacks retain ownership and cannot continue after shutdown (AC-4, AC-5); helper process checks retain existing DDC error handling (AC-6); the user performs the unplug test (AC-1).

## Build plan

1. Implement exact capture and the bounded wake helper, AC-2, AC-3, AC-4.
2. Integrate asynchronous recovery, ownership confirmation and callback guards, AC-4, AC-5, AC-6.
3. Run model, store and subprocess checks; build and launch the app, AC-2 through AC-6.
4. Repeat physical cable removal with persistent diagnostics, AC-1. Keep the PR in draft until this passes.

## Consequences

This requires additional private macOS APIs and a direct internal service mapping. Unsupported mappings fail closed. Captures cannot survive an app restart. CG IDs are usually stable, not a permanent identity contract; kernel continuity and observed reuse guards constrain this exception but cannot prove behavior on every OS version. Automated checks do not establish AC-1 and the implementation remains under physical validation.

## References

- [Apple CGDirectDisplayID](https://developer.apple.com/documentation/coregraphics/cgdirectdisplayid): usual identifier lifetime.
- [BetterDisplay release history](https://github.com/waydabber/BetterDisplay/discussions/1700): retaining disconnected IDs during an app session until reuse.
- [Clamless helper](https://github.com/TCXM/clamless/blob/main/src/helper/clamless-display.c): power on followed by a captured CG ID layout reconnect.
