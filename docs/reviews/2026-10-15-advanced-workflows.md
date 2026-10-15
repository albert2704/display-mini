# Advanced workflows verification

Date: 2026-10-15. Branch: `feature/advanced-workflows`. Scope: spec 0006.

## Automated checks

`scripts/test.sh`, `scripts/check-toolchain.sh`, `scripts/build.sh`, signing/Info.plist validation, `scripts/package.sh`, `tooling/docs/check-media.py` and `git diff --check` pass. [PR #7](https://github.com/albert2704/display-mini/pull/7) tracks the required hosted macOS build.

New coverage exercises selected brightness sources and targets, empty selection, persistence, malformed JSON and wrong preference types, backup/reset, busy targets and independent presets. Three schedule model groups and six controller groups cover validation, recurrence, DST, duplicate occurrences, clock reversal, startup and wake gaps, timezone changes, missing presets, busy controls, simultaneous rules, storage failure and completion. Four power-controller groups cover creation/release failures, replacement, deadline expiry, sleep and shutdown. Five workflow store groups include actual scheduler-to-store-to-fake-DDC success, failed writes, interruption, reconciliation and a later schedule.

Existing control, advanced control, personalization, shortcut, recovery, subprocess and helper checks pass. Store tests use isolated preferences, injected clocks and substitute hardware; they perform no physical monitor writes.

An independent agent reviewed the implementation against spec 0006. Findings about malformed selection preferences, shutdown/recovery guards and end-to-end scheduler completion coverage were resolved. The final review reported no outstanding actionable findings.

## Native verification

The production build was launched on the development Mac. Advanced shows all three workflow cards, existing monitor controls and the recovery footer. With no presets saved, adding a schedule is disabled and the card explains how to save one first.

Starting a 30-minute Keep Displays Awake session displayed its countdown. `pmset -g assertions` showed Display Mini's named `PreventUserIdleDisplaySleep` assertion, its remaining timeout and `TimeoutActionRelease`. Clicking Stop returned the card to inactive and removed the named assertion.

A separate smoke runner exercised the real IOKit backend with a two-second timeout. With no controller timer running, `IOPMAssertionCopyProperties` confirmed that macOS had removed the assertion after 3.005 seconds. Releasing the expired ID returned `kIOReturnBadArgument`, which the controller handles after its deadline.

Schedule and participant editing were exercised in a normal-window native fixture hosting the production views, temporary preferences and substitute displays. The UI created a Weekdays schedule disabled by default, enabled it, reopened it with its existing time and recurrence, changed its preset from Work to Evening while preserving enabled state, and deleted it. All screens changed to Selected screens with an initially empty list; selecting both sample displays updated their checkboxes, and the master switch toggled independently. The fixture was closed and its temporary preferences removed. Schedule timers were disabled, and no awake session was started in this fixture.

The native renderer produced updated Advanced screenshots in light and dark appearances and a schedule editor image. Images were visually inspected and media validation passed. They use sample data rather than the user's desktop. The real app remains running with no test schedules or active awake session.

## Limits

The live popover's nested preset editor could not be reliably operated through UI automation, so schedule editing was checked in the isolated native fixture. Scheduled and linked brightness writes were validated through the production store with substitute hardware, not by changing live monitor levels. Physical unplug recovery, sleep/wake and long-duration schedules were not repeated on hardware. These checks establish the implementation and power assertion behavior; they do not establish compatibility with every monitor.
