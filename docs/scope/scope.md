# Display Mini scope

**Approach:** coherent end-to-end slices, committed separately.
**Workflow:** Beta, with automated regression checks and native UI verification.

| Feature | Status | Spec |
| --- | --- | --- |
| Compact brightness, volume, resolution and connection controls | Shipped | [0001](../specs/0001-display-controls.md) |
| Monitor compatibility and connection diagnostics | Shipped | [0002](../specs/0002-monitor-compatibility.md) |
| Built-in recovery after unplug | Shipped; user confirmed live recovery | Existing recovery implementation and tests |
| Everyday controls | In progress | [0003](../specs/0003-everyday-controls.md) |

## Everyday controls

The user wants keyboard shortcuts, mute, and brightness/volume presets. Shortcuts target the screen under the pointer.

Done when controls work from the panel and registered shortcuts, presets survive relaunch, failed or missing monitor writes are explained, and recovery remains available.

- [x] Design it (spec): 0003 records the user's choices and implementation defaults.
- [ ] Build mute with confirmed volume restore (AC-1).
- [ ] Build persisted preset management and safe execution (AC-2, AC-3, AC-6).
- [ ] Build pointer-targeted shortcuts and settings (AC-4, AC-5).
- [ ] Verify the native app and update documentation.
- [ ] Run automated regression checks and publish the PR.

## Deferred

Custom shortcut bindings, media-key interception, preset schedules, preset resolution/connection changes, and network-controlled displays.
