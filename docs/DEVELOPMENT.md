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

The fixtures use synthetic serial numbers. The tests do not call macOS configuration APIs, run the monitor helper, or assert physical screen behavior. Extend tests for a new pure rule or concrete regression; do not equate a passing parser test with hardware compatibility.

## Manual hardware validation

Perform these checks only on a setup where display changes are authorized and another visible screen/recovery route is available. Record the app commit, OS, chip family, monitor model, connection path, result, and any error. Omit hardware serials and UUIDs from public reports.

| Check | Expected result |
| --- | --- |
| Launch and open panel | Real names, resolutions, and readable controls; no unknown offline slots. |
| Brightness | Correct screen changes; reported state updates; rejected writes show an error. |
| Low brightness and recovery | Software dimming appears; the shortcut removes it and restores a readable level. |
| Monitor volume | Physical monitor volume changes and readback confirms the value. |
| Resolution Revert | Previous mode returns after timeout or explicit Revert. |
| Resolution Keep | Chosen mode remains after confirmation. |
| Disconnect/reconnect | Windows leave the disconnected screen; reconnect resolves a fresh ID even when UUID disappears. |
| Last display | Final active screen cannot be disconnected. |
| Hotplug and wake | Discovery refreshes without stale control writes. |
| Quit and relaunch | Owned disconnections and pending mode records are recovered when possible. |
| Failure during recovery | Original recovery record survives, and new previews do not overwrite it silently. |

Also check keyboard navigation, long display names, the DDC panel, and both macOS appearances. Hosted CI cannot replace these checks.

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

## Updating m1ddc

The exact upstream commit is recorded in `Vendor/SOURCE.txt`. Preserve `Vendor/LICENSE`, review upstream changes, and reapply or remove local patches deliberately. `THIRD_PARTY_NOTICES.md` lists the local transport changes. Revalidate real DDC replies and all documented compatibility claims after changing the helper.
