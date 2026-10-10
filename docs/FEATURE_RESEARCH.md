# Feature research

Reviewed 2026-10-10. This comparison uses public product documentation as inspiration. It does not imply feature parity, shared implementation, or tested compatibility with every monitor those apps support.

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
* Optional synchronization across selected screens and preset scheduling.
* Carefully scoped media-key support.
* Manual resolution of duplicate monitor identities, only after a stable port mapping can be tested across reconnects.

These are candidates, not promises or implemented features. Implemented features are listed above; broader automation remains outside this update.

## Cable removal recovery investigation

[Clamless helper source](https://github.com/TCXM/clamless/blob/main/src/helper/clamless-display.c) separates active WindowServer screens from physical port state using display hints and hardware events. This informed Display Mini's independent hardware port reader after a live unplug test produced no screen transition. Display Mini parses a limited set of connection events, retains unknown states, and gates hardware recovery on coverage of the active replacement screens. Clamless also has separate panel power controls; those are not implemented here.
