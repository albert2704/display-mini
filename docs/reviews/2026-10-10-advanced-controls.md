# Advanced controls verification

Date: 2026-10-10. Branch: `feature/advanced-controls`. Scope: spec 0005.

## Automated checks

`scripts/test.sh`, `scripts/check-toolchain.sh`, `scripts/build.sh`, signing/Info.plist validation, `tooling/docs/check-media.py` and `git diff --check` pass.

New checks cover three model scenarios and five store scenarios: malformed/mismatched probes, independent unsupported controls, noncontinuous input maxima, zero current input, common input codes, exact refresh geometry and fractional rates, contrast range conversion and rollback, explicit input delivery, built-in recovery guard, stale callbacks, linked brightness persistence/debounce/skips and preset isolation. Subprocess fixtures exercise the actual DDCClient: contrast requires matching readback, mismatches fail, and an input send never follows with a read that would incorrectly report failure after losing the connection.

The existing control, personalization, shortcut, recovery and helper suites also pass. Store tests use substitutes and perform no physical monitor writes.

## Native verification

The final local build was launched through Finder on the development M1 Pro/LG IPS QHD setup.

- Starts on Displays; the native segmented picker switches to Advanced and back.
- Existing custom display name is preserved. Brightness reads remain 70% built-in, approximately 90% combined external, and external volume 100%.
- Advanced detection reads 70% contrast from the LG monitor. Its slider is available.
- The LG standard input query returns zero. The final UI explains that the input was not identified, offers compatibility guidance, and does not expose an input switch for that result.
- The external refresh menu contains 60 Hz and 75 Hz, with 75 Hz checked. The menu was dismissed without applying a mode.
- Recovery and other footer actions remain visible. The Advanced scroll area handles the longer compatibility explanation.
- The final build remains running. Restart follows the existing shutdown behavior of reconnecting displays the app had disabled; the built-in panel was restored during the update.

Production views were also rendered with isolated sample data in light and dark appearances. Advanced shows the supported input selection example, and the main panel screenshot includes the new tabs. Documentation images use synthetic names and settings, never the user's live desktop.

## Limits

No physical contrast write, input change or refresh transaction was performed. Linked brightness writes, persistence and preset isolation were validated with store tests, not a live multi-monitor brightness change. Physical unplug recovery was not repeated. These checks establish implementation behavior and read support on this connection, not compatibility with every monitor.
