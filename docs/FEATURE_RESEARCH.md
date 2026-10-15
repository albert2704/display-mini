# Feature research

Reviewed 2026-10-15. This comparison uses public product documentation as inspiration. It does not imply feature parity, shared implementation, or tested compatibility with every monitor those apps support.

## Inspiration used in this update

| Reference | Useful idea | Display Mini implementation |
| --- | --- | --- |
| [BetterDisplay DDC settings](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/ddc/) | Per-display read waits, retries and communication settings help accommodate differing monitor behavior. | Standard/Slow response timing with fixed bounds, visible attempts, and checksum validation retained. |
| [BetterDisplay DDC settings](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/ddc/) | Control ranges and communication results deserve explicit treatment. | One structured probe reports current/max together, with separate brightness and volume results. |
| [DisplayBuddy Getting Started](https://displaybuddy.app/docs/getting-started) | Clearly distinguish DDC, Apple display protocol and software control; offer a compact view with extra controls behind it. | Keep the small main panel, show the active brightness method in Monitor Controls, and place diagnostics there. |
| [DisplayBuddy troubleshooting](https://displaybuddy.app/troubleshooting) | DDC/CI settings, locked picture modes and connection paths affect whether controls work. | Explain failures and suggest targeted checks. Copy a report without identifiers for an issue the user chooses to submit. |

DisplayBuddy also documents Samsung Smart control over Wi-Fi. That would require network protocols, device pairing and separate testing; it is outside the current local DDC implementation. BetterDisplay exposes more low-level timing and control options than this app. Two bounded profiles keep this update understandable while preserving safe reads and confirmed writes.

## Everyday controls added in 0.3.0

[DisplayBuddy presets](https://displaybuddy.app/docs/presets) and its [keyboard shortcut guide](https://displaybuddy.app/docs/keyboard-shortcuts) informed named snapshots and quick activation. Display Mini saves confirmed brightness/volume for connected screens, matches by UUID, and exposes the first three presets through registered modifier shortcuts. The user explicitly selected the screen under the pointer for brightness, volume and mute keys.

Mute is implemented as confirmed volume zero with last-volume restore through the existing DDC path. This is Display Mini's own implementation choice, not a claim about another app's internals. Carbon registered hotkeys extend the existing recovery mechanism and avoid broad keyboard interception. Later user requests added editable key/modifier bindings with saved defaults and failed-edit rollback, a compact grouped key menu, and explicit keyboard recording in the foreground editor.

## Practical candidates for later

* Wake settling and per-display retry policy, to address monitors that become ready later than macOS.
* Named synchronization groups and following brightness changes made through macOS or another app.
* Sunrise/sunset schedules, connection triggers and wake settling for automation.
* Carefully scoped media-key support.
* Manual resolution of duplicate monitor identities, only after a stable port mapping can be tested across reconnects.

These are candidates, not promises or implemented features. The bounded local schedules and selected screen linking described below are included in the current implementation.

## Advanced controls

The user requested more DisplayBuddy-style functionality in an Advanced tab. [DisplayBuddy's expanded controls](https://displaybuddy.app/docs/getting-started) and [sync feature](https://displaybuddy.app/) informed contrast, input switching and optional linked brightness. [BetterDisplay](https://github.com/waydabber/BetterDisplay) also lists input, synchronization and refresh controls. Display Mini implements a bounded subset: standard DDC contrast/input, app-originated brightness edits across ready screens, and existing macOS refresh variants with Keep/Revert.

Input codes are common choices, not a monitor capability inventory. Input zero does not establish a current source. Contrast support was read successfully from the development LG monitor, but its standard input read returned zero, so input switching is disabled there. No vendor specific or Wi-Fi protocol was copied or added.

## Advanced workflows

The next Advanced update takes three small workflows from broader display utilities and implements them locally:

| Reference | Useful idea | Display Mini implementation |
| --- | --- | --- |
| [DisplayBuddy schedules](https://displaybuddy.app/docs/schedules) | Apply saved display settings at useful times of day. | Up to 12 preset schedules with a local time and every day, weekday or weekend recurrence. Rules start disabled and run only while the app is running and awake. |
| [DisplayBuddy feature guide](https://displaybuddy.app/blog/2024-04-14/ultimate-guide-to-displaybuddy) and [BetterDisplay feature comparison](https://github.com/waydabber/BetterDisplay/wiki/List-of-free-and-Pro-features) | Synchronization benefits from choosing which displays participate. | Keep the existing All screens behavior and add Selected screens. Only app brightness edits originating from a participant reach the other ready participants. |
| [BetterDisplay feature comparison](https://github.com/waydabber/BetterDisplay/wiki/List-of-free-and-Pro-features) and [Apple idle display sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep) | Keep displays available during a presentation or reading session. | Explicit 15, 30 or 60 minute sessions using a public IOKit assertion, a countdown and Stop, with an independent OS timeout and cleanup on sleep and quit. |

These are Display Mini implementation choices. The comparison does not claim another app uses the same scheduling, synchronization or power management internals. Schedules reuse confirmed preset writes, skip missed or busy occurrences, and prevent repeating a handled date after a clock reversal. They do not wake the Mac, launch the app, use network services or add permissions.

Selected screen linking stores stable identities, keeps offline participants and leaves presets independent. It does not mirror changes made outside Display Mini or calibrate physical luminance. Keep Displays Awake prevents idle sleep only; it does not override a closed lid, manual sleep or an unplugged monitor. Implementation and acceptance criteria are recorded in [spec 0006](specs/0006-advanced-workflows.md).

## Cable removal recovery investigation

[Clamless helper source](https://github.com/TCXM/clamless/blob/main/src/helper/clamless-display.c) separates active WindowServer screens from physical port state using display hints and hardware events. This informed Display Mini's independent hardware port reader after a live unplug test produced no screen transition. Display Mini parses a limited set of connection events, retains unknown states, and gates hardware recovery on coverage of the active replacement screens. Clamless also has separate panel power controls; those are not implemented here.
