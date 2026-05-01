# Installation

## Download a preview

1. Open [GitHub Releases](https://github.com/albert2704/display-mini/releases).
2. Download `Display-Mini-v<VERSION>-macOS-arm64.zip` and its matching `.sha256` file.
3. Optionally verify the download from the folder containing both files, substituting the downloaded version:

   ```sh
   shasum -a 256 -c Display-Mini-v0.1.0-macOS-arm64.zip.sha256
   ```

4. Expand the archive and move `Display Mini.app` to Applications.
5. Quit other display control apps, then open Display Mini. Its panel opens from a monitor icon in the menu bar.

Checksums detect damaged or mismatched downloads. A checksum hosted next to a binary is not an independent signature of the publisher.

## Signing and macOS protection

The preview is ad hoc signed locally. It has no Developer ID certificate or Apple notarization ticket. macOS may refuse a downloaded copy or show an unidentified developer message. This release does not provide a seamless notarized installation path.

If you prefer to inspect and compile the source, use the source workflow below. Do not disable system security protections to install the app. Maintainers planning wider distribution should follow the signing notes in [Development](DEVELOPMENT.md).

## Build locally

The supported target is Apple Silicon and macOS 14 or later. Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

Then clone and build:

```sh
git clone https://github.com/albert2704/display-mini.git
cd display-mini
./scripts/build.sh
./scripts/test.sh
open "dist/Display Mini.app"
```

The output is a complete app at `dist/Display Mini.app`, including the monitor helper and licenses. Building the Swift executable alone with Swift Package Manager does not assemble that bundle; use the supported script for an installable app.

Caches and compiler compatibility overlays stay under `.build`; generated app and helper outputs are ignored by Git. The scripts do not alter the installed compiler or SDK. There is no dependency download step.

## Permissions and startup

The app does not request administrator privileges, Accessibility access, Screen Recording access, or a login. Its recovery shortcut uses the macOS hotkey API. A shortcut conflict is reported in the panel, and the footer recovery button remains available.

Automatic launch at login is not configured by the app. If wanted, add the installed app yourself in macOS Login Items. Preferences and recovery records stay in the local user account.

## Update

Quit the running app using its power icon before replacing the bundle. Normal quit attempts to reconnect displays disconnected by Display Mini and revert an unconfirmed resolution. Replace the installed app and reopen it. Preferences use the same application identifier across these releases.

There is no automatic update service. Check GitHub Releases for new versions.

## Remove

First restore your screens and quit Display Mini. Remove the app from Applications and remove its Login Item if you added one.

The preference domain is `dev.albert.DisplayMini`. If you choose to remove those preferences, reconnect all screens and resolve pending recovery first: deleting the records also deletes the app's knowledge of displays it disconnected.
