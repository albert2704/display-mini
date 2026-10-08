# Feature research

Reviewed 2026-10-09. This comparison uses public product documentation as inspiration. It does not imply feature parity, shared implementation, or tested compatibility with every monitor those apps support.

## Inspiration used in this update

| Reference | Useful idea | Display Mini implementation |
| --- | --- | --- |
| [BetterDisplay DDC settings](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/ddc/) | Per-display read waits, retries and communication settings help accommodate differing monitor behavior. | Standard/Slow response timing with fixed bounds, visible attempts, and checksum validation retained. |
| [BetterDisplay DDC settings](https://betterdisplay.pro/guide/interface-reference/settings/displays/display/device-control/ddc/) | Control ranges and communication results deserve explicit treatment. | One structured probe reports current/max together, with separate brightness and volume results. |
| [DisplayBuddy Getting Started](https://displaybuddy.app/docs/getting-started) | Clearly distinguish DDC, Apple display protocol and software control; offer a compact view with extra controls behind it. | Keep the small main panel, show the active brightness method in Monitor Controls, and place diagnostics there. |
| [DisplayBuddy troubleshooting](https://displaybuddy.app/troubleshooting) | DDC/CI settings, locked picture modes and connection paths affect whether controls work. | Explain failures and suggest targeted checks. Copy a report without identifiers for an issue the user chooses to submit. |

DisplayBuddy also documents Samsung Smart control over Wi-Fi. That would require network protocols, device pairing and separate testing; it is outside the current local DDC implementation. BetterDisplay exposes more low-level timing and control options than this app. Two bounded profiles keep this update understandable while preserving safe reads and confirmed writes.

## Practical candidates for later

* Wake settling and per-display retry policy, to address monitors that become ready later than macOS.
* Saved brightness/volume presets and optional synchronization across selected screens.
* Keyboard shortcuts and monitor mute with a volume-zero fallback.
* Manual resolution of duplicate monitor identities, only after a stable port mapping can be tested across reconnects.

These are candidates, not promises or implemented features. The current update focuses on the compatibility and diagnostics requested by the user.
