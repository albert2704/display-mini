# Development and releases

## Toolchain and build outputs

Use an Apple Silicon Mac with Command Line Tools and Swift 5.9 or newer. The app deployment target is macOS 14. The build script sets both the Swift executable and Objective-C helper to arm64/macOS 14, then signs the bundle locally.

```sh
./scripts/check-toolchain.sh
./scripts/test.sh
./scripts/build.sh
./scripts/package.sh
```

| Output | Purpose |
| --- | --- |
| `.build/checks/ControlChecks` | Standalone logic test executable. |
| `.build/checks/StoreChecks` | Store, shortcut and workflow checks with substituted hardware. |
| `.build/checks/ProcessChecks` | Bounded DDC subprocess checks with temporary fixtures. |
| `.build/checks/ProtocolChecks` | Objective-C helper protocol checks without monitor I/O. |
| `.build/release/DisplayMini` | Compiled application executable. |
| `Vendor/m1ddc` | Compiled monitor helper. |
| `dist/Display Mini.app` | Complete local app bundle. |
| `dist/Display-Mini-v<VERSION>-macOS-arm64.zip` | Distribution archive. |
| Matching `.zip.sha256` | Archive checksum. |

Generated outputs are ignored by Git. Both licenses and third party notices are copied into the app's Resources directory. A failed build or version mismatch should stop packaging rather than ship an older binary.

## Swift Package Manager

`Package.swift` describes the source modules and the `ControlChecks` executable. The supported scripts call the compiler directly because some Command Line Tools installations have mismatched SwiftPM manifest modules and libraries.

On a consistent Swift installation, `swift build` and `swift run ControlChecks` are useful for editing and checking modules. They do not assemble the app bundle or compile/copy the monitor helper. Use `scripts/build.sh` to produce the runnable application.

## Compiler compatibility overlay

`scripts/toolchain.sh` checks for two module maps defining `SwiftBridging`. If both exist, it creates a VFS overlay mapping one duplicate map to an empty file for this compiler invocation. All files live under `.build/compat`, and caches remain in `.build`.

The workaround does not edit Command Line Tools, select another Xcode installation, or install packages. Do not add global compiler modifications to fix a local build.

## Automated checks

`scripts/check-toolchain.sh` verifies compiler options for both clean and duplicate module map layouts under macOS Bash. It uses temporary fixtures and never changes the installed SDK.

The assertion runner in `Tests/DisplayCoreTests` currently exercises:

1. Rejection of invalid, negative, malformed, and out-of-range monitor readings.
2. Scaling against monitor-reported maxima and clamping abnormal inputs.
3. Combined brightness continuity and hardware reading round trips.
4. The last display protection rule.
5. Resolution choice preserving density and refresh rate.
6. Disconnected identity matching, changed IDs, absent devices, and ambiguous matches.
7. Structured probes, wrong display UUIDs, invalid ranges, schema/timing mismatches, and independent control failures.
8. Timing defaults, diagnostic report privacy, and unavailable or ambiguous routes.

The fixtures use synthetic serial numbers. The tests do not call macOS configuration APIs, run the monitor helper, or assert physical screen behavior. Extend tests for a new pure rule or concrete regression; do not equate a passing parser test with hardware compatibility.

`PanelWakeBudgetTests` verifies the fixed retry count, spacing, in-flight suppression and invalid or backwards time. `Tests/PanelWakeTests` compiles the real native helper and rejects malformed commands, invalid CG identities and a nonexistent registry service without calling panel power APIs. Store recovery fixtures exercise missing identity, deferred wake completions, ownership retention and stale callback suppression. The direct CG identity fallback was removed after physical testing showed that the saved ID also becomes unavailable. A local read-only probe verified exact CoreDisplay to kernel service mapping; it does not establish that waking that service fixes unplug recovery.

`Tests/DDCProcessTests` launches temporary shell fixtures to test success, missing helper, nonzero exit, explicit diagnostic exit codes, signal termination, output overflow, timeout, and an inherited pipe held by a child. Ordinary DDC commands still require exit zero. `Tests/HelperTests` compiles selected helper functions and tests packet validation, EDID matching, duplicate identities, selectors, and delay bounds without doing monitor I/O. `scripts/test.sh` runs all suites. SwiftPM's `ControlChecks` runs only the pure Swift suite.

`Tests/DisplayStoreTests` compiles the production store against native/DDC substitutes. It drives real debounce and completion paths without monitor I/O: sequential preset writes, partial failure, canceled late replies, reconciliation before saving, mute rollback, recovery writes, and shortcut guards. Nine additional shortcut scenarios cover validation, failed-edit rollback, reset/recovery/event dispatch, independent conflicts, persistence, keyboard recording, invalid input and cancel, foreground/editor scope, and capturing registered keys without display actions. Tests inject a registrar, isolated UserDefaults and synthetic AppKit events; the lifecycle scenario also installs a local monitor and posts blur notifications to check cleanup. They do not register global hotkeys. `DisplayStore(startMonitoring: false)` skips automatic OS observation/recovery during this fixture setup.

Four additional model scenarios cover personalization names, separate screen identities, resolution variants, malformed documents and count limits. Three store scenarios cover persisted names, rejection/removal of unavailable favorites, and isolated backup/reset. Direct Swift build scripts use whole module compilation so multiple DisplayCore source files produce one linked object.

Advanced controls add three model scenarios for probes, input codes and exact refresh geometry; five store scenarios for contrast rollback, input delivery/recovery guards, stale operations, linked edits/persistence and preset isolation; and real DDCClient subprocess fixtures proving that input sends do not attempt readback while contrast does. A zero current input must not enable switching or suppress valid contrast support.

Advanced workflows add these checks to the same runners:

| File | Coverage |
| --- | --- |
| `Tests/DisplayCoreTests/BrightnessSelectionTests.swift` | All-screen migration, selected membership, empty selection, canonical identity and malformed/unsupported storage. |
| `Tests/DisplayCoreTests/ScheduleTests.swift` | Three scenarios for library bounds and validation, recurrence/strict DST matching, and daily history with clock reversal and invalid dates. |
| `Tests/DisplayStoreTests/AutomationTests.swift` | Six scenarios for consumption before dispatch, execution completion, missing/busy/simultaneous rules, startup and sleep gaps, edits, date reversal, relaunch, timezone/DST and storage recovery. |
| `Tests/DisplayStoreTests/KeepAwakeTests.swift` | Four scenarios for OS timeout/release properties, assertion ownership, expiry/lifecycle and creation/release failure handling. The backend is fake. |
| `Tests/DisplayStoreTests/WorkflowStoreTests.swift` | Five scenarios for selected source/target behavior, fail-closed preferences and backups, busy targets, recovery guards, and scheduled preset outcomes through the actual store. |

The scheduled-execution integration case advances an injected clock and completes fake DDC writes to verify success, failed writes, interruption, reconciliation and a later schedule. It checks the bridge between controller status and the existing preset executor. Use `presetDefaults`, `automationController` and `keepAwakeController` injection when a test needs isolated persistence, manual time or a fake power backend. `startMonitoring: false` skips automatic observation and timers; it does not by itself replace a power backend if a test explicitly calls Start. The store runner compiles both workflow controllers explicitly, so keep `scripts/test.sh` in sync when adding dependencies.

## Manual hardware validation

For an explicitly authorized read-only hardware check, the bundled helper accepts `--delay-ms 50 display <UUID> probe` (or 150 for Slow). It returns schema 1 JSON. This internal output includes the requested UUID; use the app's **Copy Report** for public issue reports. Detection sends Get VCP requests and never Set VCP commands.

Perform these checks only on a setup where display changes are authorized and another visible screen/recovery route is available. Record the app commit, OS, chip family, monitor model, connection path, result, and any error. Omit hardware serials and UUIDs from public reports.

| Check | Expected result |
| --- | --- |
| Launch and open panel | Real names, resolutions, and readable controls; no unknown offline slots. |
| Brightness | Correct screen changes; reported state updates; rejected writes show an error. |
| Low brightness and recovery | Software dimming appears; the shortcut removes it and restores a readable level. |
| Monitor volume | Physical monitor volume changes and readback confirms the value. |
| Mute and unmute | Zero is confirmed, then the previous positive volume returns; a failed write rolls back. |
| Preset lifecycle | Save, rename, apply, relaunch and delete; verify all matching screens and no others. |
| Preset interruption | Restore/sleep/hotplug stops remaining steps; controls reconcile after a late write. |
| Everyday shortcuts | Pointer-targeted actions, first three preset slots, enable switch, change/reset keys and conflicts; custom recovery and the fixed fallback work when everyday keys are off. |
| Keyboard recording | Record a combination, review and Save; reject duplicate/reserved keys; Escape, Stop, app/window blur and editor closure stop listening; existing registered keys do not run actions in the foreground editor. |
| Display personalization | Rename a screen, refresh/relaunch, restore its system name; star/unstar a mode and confirm menu placement and persistence without changing the mode. |
| Favorite resolution | Select a different favorite and check Keep/Revert. Reconnect with changed availability and ensure missing favorites cannot apply or route to another screen. |
| Advanced navigation | Both tabs remain accessible; recovery and Keep/Revert stay visible. Inspect light and dark layouts and scrolling. |
| Advanced detection | Detect performs only reads, contrast/input report independently, input zero leaves switching unavailable. |
| Contrast | Release the slider, verify the actual monitor change and readback; a failed write restores the displayed value. |
| Input | Confirm only on an authorized test setup, check physical source change and return using monitor buttons. Cancel must issue no command; sent does not mean confirmed. |
| Linked brightness | Master toggle and participant edits alone change no levels. All mode retains existing behavior; Selected mode fans out only from included sources to ready included targets. Empty selection links nothing, disconnected membership survives, and presets retain independent levels. Relaunch preserves mode and members. |
| Schedule editor | Create, edit, enable, disable and delete a rule; new rules start disabled. Check missing presets, empty state, local time and recurrence, persistence and the 12-rule limit. |
| Schedule execution | On an authorized setup, a due enabled rule uses the saved preset; status changes from Started only after completion. Busy/recovery states skip it without retry, and simultaneous rules start at most one preset. |
| Schedule lifecycle | Quit/relaunch or sleep across a due time produces no catch-up. Keep deterministic clock/DST cases in automated tests; do not change the host clock to exercise them. |
| Keep Displays Awake | Start shows a countdown and named assertion; Stop removes it. Sleep/quit ends ownership, relaunch starts off, and a short backend smoke test verifies OS timeout independently of the controller timer. |
| Refresh rate | List only the current geometry; select another rate, verify Keep/Revert and no size or density change. |
| Response timing | Switching Standard/Slow changes the reported wait to 50/150 ms and starts read-only detection. |
| Diagnostics | Brightness and volume show separate results, attempts, ranges and the last check time. |
| Copy Report | Copies safe diagnostic fields without UUID, serial, display name or registry/local path. |
| Duplicate identities | Refuses DDC routing when two online screens share vendor/model/serial, even if metadata is missing on one. |
| Resolution Revert | Previous mode returns after timeout or explicit Revert. |
| Resolution Keep | Chosen mode remains after confirmation. |
| Disconnect/reconnect | Windows leave the disconnected screen; reconnect resolves a fresh ID even when UUID disappears. |
| Last display | Final active screen cannot be disconnected. |
| Hotplug and wake | Discovery refreshes without stale control writes. |
| Quit and relaunch | Owned disconnections and pending mode records are recovered when possible. |
| Failure during recovery | Original recovery record survives, and new previews do not overwrite it silently. |

Also check keyboard navigation, long display names, the DDC panel, and both macOS appearances. Hosted CI cannot replace these checks.

Keep Displays Awake can be checked without writing monitor settings: inspect the named Display Mini assertion with `pmset -g assertions`, then stop the session and confirm it disappears. On 2026-10-15, a separate native backend smoke check created a two-second assertion and observed automatic OS release after approximately three seconds with no controller timer running. That proves timeout ownership on the tested host; it does not establish end-to-end idle-sleep behavior on every supported macOS version. Keep this smoke check separate from the default fake-backend suite.

## GitHub Actions

`.github/workflows/ci.yml` runs on the standard Apple Silicon `macos-26` hosted runner. It executes tests, compiles the app/helper, validates signatures, checks architecture and deployment targets, and packages an artifact. It does not launch the app or manipulate displays.

Actions are pinned to immutable commits, with readable version comments. The workflow has read access to repository contents and does not receive signing credentials. GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) describes available images and architectures.

## Prepare a release

1. Update `VERSION` with a numeric `major.minor.patch` value.
2. Update `CHANGELOG.md` and add `docs/releases/v<VERSION>.md`, including validation limits.
3. Run tests, build, and package. Check the app and helper architectures and minimum OS:

   ```sh
   lipo -archs "dist/Display Mini.app/Contents/MacOS/DisplayMini"
   lipo -archs "dist/Display Mini.app/Contents/Helpers/m1ddc"
   xcrun vtool -show-build "dist/Display Mini.app/Contents/MacOS/DisplayMini"
   xcrun vtool -show-build "dist/Display Mini.app/Contents/Helpers/m1ddc"
   codesign --verify --deep --strict "dist/Display Mini.app"
   ```

4. Commit the source and documentation, push, and wait for CI.
5. Tag the reviewed commit. Publish the ZIP and matching checksum with that version's release notes. Use a GitHub prerelease while hardware validation or distribution readiness remains incomplete.

The repository CI uploads build artifacts but does not automatically publish releases. Release assets must correspond to the tagged source.

## Wider distribution

The default scripts perform ad hoc signing, not Developer ID signing or notarization. A maintainer distributing polished downloads needs an Apple Developer ID, an appropriate signing/notarization process, and validation of the nested helper with that process. Keep credentials out of source, issue reports, and public logs. Do not label a release notarized until its actual archive has passed that process.

## Documentation images and walkthrough

The README and user guide use native SwiftUI examples with isolated sample data. `python3 tooling/docs/render-screens.py` compiles a separate renderer with hardware substitutes; it does not launch the app or change display settings. The optional HyperFrames project under `tooling/docs/walkthrough` assembles a silent, captioned video from those images. See [media provenance and regeneration](media/README.md) for commands, limitations and validation. Video tooling is not part of the application build or a runtime dependency.

## Updating m1ddc

The exact upstream commit is recorded in `Vendor/SOURCE.txt`. Preserve `Vendor/LICENSE`, review upstream changes, and reapply or remove local patches deliberately. `THIRD_PARTY_NOTICES.md` lists the local transport changes. Revalidate real DDC replies and all documented compatibility claims after changing the helper.
