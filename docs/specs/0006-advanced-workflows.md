# 0006. Advanced workflows

**Date**: 2026-10-15
**Status**: In Progress
**Authorization**: The user delegated the next functionality update and agent orchestration. These defaults extend the existing Advanced tab and can be changed through its controls.

## Summary and decision

Add local preset schedules, selected participants for linked brightness, and timed Keep Displays Awake sessions. Reuse SwiftUI, PanelStyle, UserDefaults, the preset executor, and public IOKit power assertions. No dependency, network service, or permission is added. Build each complete path separately, then verify their integration.

## Requirements

- **AC-1**: Advanced contains compact cards for linked brightness, Keep Displays Awake, and preset schedules, followed by the existing monitor cards. Displays and its recovery controls retain their current behavior. Empty, invalid storage, busy, missing preset and operation failure states are visible.
- **AC-2**: Linked brightness retains all connected screens by default, including existing installations. A user can choose Selected screens and persist individual stable UUIDs. An empty selection links nothing. Only edits originating from a participating screen fan out, and only ready participating targets receive the change. Selecting participants never changes hardware. Presets remain independent.
- **AC-3**: Users can create, edit, enable, disable and delete up to 12 schedules. Each selects an existing preset, local hour and minute, and Every day, Weekdays or Weekends. New schedules start disabled. Store versioned JSON locally and validate IDs, bounds and uniqueness. Corrupt or unsupported storage remains untouched until an explicit reset backs it up.
- **AC-4**: Schedules run only while the app is running and awake. Each schedule is handled at most once per local calendar date. Record consumption before invoking the existing preset executor. Skip missed times after launch, wake or a timer gap over 90 seconds. Clock reversal resets the baseline; timezone changes reset the baseline. A deleted preset, busy controls or no matching connected display produces a skipped result rather than retries. Simultaneous rules are consumed together, with only the first eligible rule started. Status says Started until the existing preset executor confirms completion or failure.
- **AC-5**: Keep Displays Awake offers 15, 30 and 60 minute sessions, a visible remaining time and Stop. It is off at launch. Use a named PreventUserIdleDisplaySleep assertion with OS timeout and release action, plus explicit release on stop, expiry, sleep and app termination. Starting a replacement must not leak the prior assertion. Creation failure is visible and must not claim an active session. It prevents idle display sleep; it does not override closing the lid, manual sleep or a disconnected display.
- **AC-6**: Unit and integration checks use injected clocks/defaults/power backends and fake display writes. Cover schedule deduplication, sleep gaps, DST, clock reversal, missing presets, busy controls, bad storage, selected source/target behavior, and assertion ownership. Verify the real UI and a short lived power assertion without changing actual monitor brightness as an automated test.

## Value sources and persistence

| Value | Source |
| --- | --- |
| Preset name, ID and levels | Existing PresetLibrary and DisplayPreset, no copy of levels in a schedule |
| Schedule | UUID, preset UUID, hour 0...23, minute 0...59, recurrence enum, enabled boolean from editor |
| Schedule due time | Injected Date clock and Calendar.autoupdatingCurrent in production, strict calendar matching for DST gaps |
| Handled occurrence | Schedule UUID plus local year/month/day; persisted separately from schedule configuration |
| Schedule status | Controller evaluation result; applied/failed outcome remains the existing presetMessage |
| Linked participants | Existing stable display UUIDs; persisted mode and explicit UUID set; absent storage means all screens |
| Display names and availability | Existing displays, connected state and aliases |
| Session duration | Fixed 15/30/60 minute options; remaining duration from injected monotonic uptime |
| Power operation result | IOPMAssertionCreateWithProperties and IOPMAssertionRelease through an injectable backend |

Schedules live under `presetSchedules` with a versioned library and `presetScheduleOccurrences` for daily consumption. The controller owns validation and edits. Missing target presets stay visible so users can retarget or delete the rule. Reset backs up invalid bytes. Updating a schedule does not clear a consumed date, preventing duplicate execution by toggling or editing within the day. A new rule does not retroactively fire within its creation minute.

Daily consumption uses a validated high water date or equivalent ledger so moving the clock from date A to B and back to A cannot repeat an earlier execution. Invalid occurrence storage also fails closed. The integration guard explicitly rejects shutdown and unresolved resolution recovery in addition to the existing preset readiness check. Completion and interruption feed the scheduler result through `completeActivePreset(message:succeeded:)`.

Selected brightness mode uses a new versioned `BrightnessLinkSelection` model under `brightnessLinkSelection`; the existing `linkedBrightnessEnabled` master switch remains authoritative. All mode includes newly connected displays. Selected mode retains temporarily disconnected members and lists them using a shortened identity if no known name exists. Malformed selection fails closed and shows a reset action rather than reverting to all screens.

Linked targets skip active writes and pending volume changes. Pending brightness edits coalesce to the newest value, retaining the existing rapid slider behavior.

## Implementation contracts and ownership

The scheduling agent owns `Sources/DisplayCore/PresetSchedule.swift`, `Sources/DisplayMini/PresetAutomationController.swift`, `Sources/DisplayMini/PresetAutomationView.swift` and new schedule test files. Its controller has no concrete DisplayStore dependency. It exposes observable library/status/error state, edit methods, `start(presets:canApply:apply:)`, `suspend()`, `resume()`, `shutdown()` and an injectable/manual `evaluate()` path. Providers are closures, with weak store capture at integration. `apply` returns whether the existing executor accepted the request. The view takes the controller and current preset list, inheriting PanelStyle.

The power agent owns `Sources/DisplayMini/KeepAwakeController.swift`, `Sources/DisplayMini/KeepAwakeView.swift` and a new power test file. It exposes `start(minutes:)`, `stop()`, `shutdown()`, observable active/remaining/error state and an injected backend plus monotonic clock. Its view takes the controller. Tests use a fake backend; the main thread will wire the test runner.

The orchestrator owns the brightness selection model/tests and all shared integration files: DisplayStore, AdvancedView, AppMain if needed, test/build scripts, documentation and commits. The store owns both controllers, starts scheduling only when startMonitoring is true, suspends on willSleep, resumes after wake and shuts both down at termination. Keep awake ends on sleep. Defaults and controllers remain constructible without timers or real hardware effects in tests and documentation previews.

## Design

Use the existing 300 point Advanced panel and its small system typography. The brightness card offers an All screens / Selected screens menu under the master toggle, with participant checkboxes only in selected mode. Keep Awake shows a small duration menu and Start or Stop. Schedules show an Add affordance, concise rows with enabled state and edit/delete actions, and a compact editor sheet. Explain the running and awake requirement next to the schedules. Recovery, errors and Keep/Revert remain outside the scrolling tabs.

## Build plan

1. Build schedules and deterministic evaluation tests, AC-3 and AC-4.
2. Build power assertion ownership and native card, AC-5.
3. Build selected brightness participants and guards, AC-2.
4. Integrate lifecycle and Advanced cards, run full regression and native checks, AC-1 and AC-6.
5. Update user guides, feature research and screenshots, publish a reviewed PR.

## Rationale and consequences

Daily schedules reuse verified sequential preset application instead of adding a second monitor writer. Selected membership is a smaller extension than arbitrary named groups. Timed power assertions give a bounded presentation mode without hidden indefinite settings. Connection triggers, sunrise schedules, wake retries, rotation and media key interception remain future work. Schedules intentionally do not catch up after downtime, and they do not wake the Mac.

## References

- [DisplayBuddy schedules](https://displaybuddy.app/docs/schedules)
- [DisplayBuddy feature guide](https://displaybuddy.app/blog/2024-04-14/ultimate-guide-to-displaybuddy)
- [BetterDisplay feature comparison](https://github.com/waydabber/BetterDisplay/wiki/List-of-free-and-Pro-features)
- [Apple idle display sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep)
- Existing specs 0003 and 0005, DisplayStore preset executor and AdvancedView.
