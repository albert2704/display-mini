# Troubleshooting

## Read the connection report first

Open **Monitor Controls…**, run **Detect Again**, and check brightness and volume separately. If replies are intermittent, select **Slow** and compare the result. A slow profile changes only communication waits; it does not change the monitor's brightness or volume.

| Result | Meaning and next step |
| --- | --- |
| Responding | A valid current value and maximum were received. The raw range need not be 0–100. |
| Not supported by monitor | The monitor explicitly rejected that VCP control. Software dimming can still control brightness. |
| No valid reply | Check DDC/CI, try a Custom picture mode, Slow timing, and a direct cable connection. |
| Request/reply I/O failure | macOS could not complete the DDC transfer. Try another port or cable; check the dock's support. |
| Invalid control range | Hardware control stays disabled because safe scaling is unknown. Retry; do not assume a maximum of 100. |
| No verified DDC route | No external service had a readable, valid EDID matching this screen. Private API availability, virtual connections or adapters may be involved. |
| DDC route is ambiguous | More than one display has the same identity, or multiple services match. The app refuses to guess which screen to change. |
| Check timed out | The helper exceeded its deadline. Reconnect the cable and retry. |

Use **Copy Report** for a report with device identifiers omitted. Add the monitor model, cable/dock model, and steps yourself when opening an issue. The app cannot infer a cable or dock model from a failed DDC reply. A report is copied locally and is never sent automatically.

## Brightness says Software

Native or DDC brightness was unavailable, or software mode was selected. Open Monitor Controls, check the software setting, and choose Detect Again. Enable DDC/CI in the monitor's menu. If a dock or adapter is involved, test a direct connection when practical.

A valid DDC response must contain the requested control, successful status, matching checksum, and a positive range. Incomplete or invalid data is not treated as hardware support.

## Volume is unavailable or sound does not change

Volume support is independent of brightness. Check that the monitor has speakers, reports DDC volume, and receives audio from the selected macOS output. The app cannot change Mac system volume or make unsupported firmware implement DDC volume.

## Values jump back

Quit other display utilities while testing. Automatic brightness, monitor settings, another app, or a rejected write can change measured values. An error after a write means the monitor did not confirm the requested value. Refresh and check the monitor's own menu before retrying.

Combined slider values include a software range and do not map one to one to physical backlight percentages.

## A screen will not reconnect

1. Use its switch or Control + Option + Command + R.
2. Read the error and confirm the screen is physically connected.
3. Reconnect its cable if macOS no longer exposes it.
4. Use macOS Displays settings or log out if the OS cannot restore the connection.

The app retains owned disconnect records for retry. Do not erase preferences while a screen is disconnected. Identical monitors with missing serial identities can be ambiguous, and private APIs may change after a macOS update.

## A resolution preview looks wrong

Wait for the 15 second revert, choose Revert, or use recovery. If the screen was unplugged during preview, reconnect it first. Previous modes can disappear when the monitor, cable, refresh support, or OS changes. In that case choose a usable mode in macOS Displays settings, then acknowledge the current resolution in the app's recovery prompt.

The timeout cannot guarantee restoration after every WindowServer or hardware failure.

## No displays appear

Run the packaged app in a normal logged in desktop session. A terminal sandbox, CI runner, remote noninteractive process, or unavailable WindowServer can prevent discovery. Refresh after reconnecting a display.

CoreGraphics excludes disconnected displays from its online list. The app also queries SkyLight, but availability remains OS dependent.

## The restore shortcut is unavailable

Another app may own Control + Option + Command + R. Use the footer's curved arrow instead. Display Mini reports registration failures and does not replace another app's shortcut.

## The downloaded app is blocked

Preview archives are not notarized or Developer ID signed. See [Installation](INSTALLATION.md) for building from source. Do not disable Gatekeeper, SIP, or other system protections to use this project.

## Build errors

| Symptom | What to check |
| --- | --- |
| `xcrun` or `swiftc` missing | Install Command Line Tools and check `xcode-select -p`. |
| Duplicate `SwiftBridging` module | Use the scripts. They detect duplicate maps and supply a local VFS overlay. |
| SwiftPM manifest library mismatch | `scripts/build.sh` and `scripts/test.sh` do not require SwiftPM manifest execution. |
| Module cache permission error | Scripts put caches under `.build`; check that the checkout is writable. |
| Architecture mismatch | Use the current build script, which rebuilds the helper for arm64. Intel app support is not included. |
| Helper missing | Launch `dist/Display Mini.app`, which includes `Contents/Helpers/m1ddc`. |

## Report a compatibility issue

Use a [bug report](https://github.com/albert2704/display-mini/issues/new/choose) with app version or commit, macOS version, chip family, monitor model, cable/dock/adapter path, which controls work, exact error text, and reproduction steps. Mention other display utilities that were running.

Remove monitor serials, display UUIDs, usernames, and unrelated desktop content from diagnostics or screenshots. Never include tokens or private files. Security concerns belong in [private reports](../SECURITY.md).
