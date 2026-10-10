# Display Mini scope

**Approach:** coherent end-to-end slices, committed separately.
**Workflow:** Beta, with automated regression checks and native UI verification.

| Feature | Status | Spec |
| --- | --- | --- |
| Compact brightness, volume, resolution and connection controls | Shipped | [0001](../specs/0001-display-controls.md) |
| Monitor compatibility and connection diagnostics | Shipped | [0002](../specs/0002-monitor-compatibility.md) |
| Built-in recovery after unplug | Shipped; user confirmed live recovery | Existing recovery implementation and tests |
| Everyday controls | In progress | [0003](../specs/0003-everyday-controls.md) |
| Custom screen names and favorite resolutions | Built; awaiting merge | [0004](../specs/0004-display-personalization.md) |

## Everyday controls

The user wants keyboard shortcuts, mute, and brightness/volume presets. Shortcuts target the screen under the pointer.

Done when controls work from the panel and registered shortcuts, presets survive relaunch, failed or missing monitor writes are explained, and recovery remains available.

- [x] Design it (spec): 0003 records the user's choices and implementation defaults.
- [x] Build mute with confirmed volume restore (AC-1).
- [x] Build persisted preset management and safe execution (AC-2, AC-3, AC-6).
- [x] Build pointer-targeted shortcuts and settings (AC-4, AC-5).
- [x] Add editable shortcut bindings and registration/persistence checks (AC-7, user follow-up).
- [x] Add keyboard recording with cancellation and safe capture of registered keys (AC-8, user follow-up).
- [ ] Verify the native app and update documentation.
- [x] Run automated regression checks and publish the PR.

Implementation and automated checks were merged in [PR #3](https://github.com/albert2704/display-mini/pull/3). Native mute and preset lifecycle checks passed. Physical shortcut delivery remains a separate validation item; automated key injection did not exercise that event path. See [native verification](../reviews/2026-10-10-native-verification.md).

## Display personalization

Display personalization adds local screen aliases and favorites while reusing the resolution confirmation and recovery flow. Code in `Sources/DisplayCore/DisplayPersonalization.swift`, `Sources/DisplayMini/DisplayStore.swift`, and `Sources/DisplayMini/DisplaySettingsView.swift`. [Verification](../reviews/2026-10-10-display-personalization.md) records the native checks and their limits.

- [x] Define behavior and storage in spec 0004.
- [x] Build names, favorites, persistence and the native settings controls.
- [x] Run seven new regression scenarios and the existing test suites.
- [x] Verify native name/star persistence and inspect light/dark layouts; update guides.
- [ ] Merge [PR #5](https://github.com/albert2704/display-mini/pull/5).

## Deferred

Media-key interception, preset schedules, preset resolution/connection changes, and network-controlled displays.
