# Changelog

## 0.2.0 — Unreleased

### Added

* Per-display Standard and Slow DDC response profiles.
* Connection diagnostics with separate brightness/volume outcomes, raw ranges, attempts and last check time.
* Copyable diagnostic reports with device identifiers omitted.
* Structured single-process detection, broader discovery up to 64 online screens, and EDID-verified service matching.
* Protocol, identity, probe privacy and bounded subprocess regression tests.

### Fixed

* Built in displays disabled by Display Mini now recover automatically after the last active external screen is unplugged. Recovery retries during display enumeration changes and waits while the lid is closed or the Mac is asleep.
* Discovery truncation after four online displays and unsafe missing metadata.
* Ambiguous service and duplicate monitor identity selection.
* Output pipe deadlocks, oversized helper output and reader lifetime after timeout.
* Settings remaining disabled after pending native/software slider work.

### Limits

* Readable EDID and a unique vendor/model/serial identity are required for DDC routing.
* Slow timing cannot add hardware DDC support to an incompatible connection.
* Live read tests cover one LG IPS QHD; new routing is not broadly hardware validated.

Changes are recorded by release. Display Mini is an early preview; hardware compatibility and physical mutation testing remain incomplete.

## [0.1.0] - 2026-10-08

### Added

* Native macOS menu bar panel with per-display brightness, resolution, external monitor volume, and connection controls.
* Native and DDC brightness with software dimming fallback and a combined lower brightness range.
* DDC detection, response validation, bounded retries, process timeouts, and write readback.
* Resolution previews with 15 second revert and persisted recovery.
* Last display protection, owned-disconnection recovery, and a global restore shortcut.
* MIT project license, vendored dependency attribution, public documentation, build scripts, CI, and release packaging with checksums.

### Fixed during initial development

* Reconnection identity handling when macOS omits a disconnected display's UUID.
* DDC read timing, response offsets, packet lengths, checksums, and integer copy sizes.
* Stale brightness callbacks and pending edits reapplying dimming after recovery.
* Lost or overwritten resolution recovery records after failed rollback.
* Monitor helper deployment target differing from the application's macOS 14 target.

### Known limitations

* Apple Silicon only; uses private macOS APIs.
* DDC support varies by monitor, cable, and adapter.
* Downloaded previews are not notarized or Developer ID signed.
* Automated tests cover pure logic, not physical DDC, resolution changes, or connection transactions.

[0.1.0]: https://github.com/albert2704/display-mini/releases/tag/v0.1.0
