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

## Linked brightness does not reach a screen

Under **Advanced**, check that **Link brightness** is on. **All screens** includes newly connected screens; **Selected screens** includes only the checked screens. Both the screen you edit and the screens receiving the change must participate. An empty selection links nothing, and editing an unchecked screen affects only that screen.

Linked targets must be connected and ready. Wait for detection, pending volume changes, active writes or advanced operations to finish, then try a brightness edit again. Changing the participant selection does not itself change brightness. Presets retain their saved levels and changes made in macOS or other apps are not followed.

An unreadable selection pauses linking. **Reset Selection** backs up the unreadable data and starts with no selected screens. Select your participants again afterward. An **Offline screen** row retains a remembered identity; reconnect that screen or uncheck it if you no longer use it.

## A preset schedule did not run

Check the schedule's enabled switch, preset, recurrence and local time under **Advanced**. New schedules start disabled. Display Mini must already be running and the Mac must be awake when the time arrives. Launching or waking after that time does not catch up, and creating a rule within its scheduled minute does not make it run immediately.

The schedule result explains a missing preset, busy controls, unresolved resolution recovery, no connected matching screens or a simultaneous schedule. Those occurrences are skipped without retries. If you want the preset now, use **Apply** in the footer's Presets panel once the issue is resolved. Editing or toggling a schedule does not allow a second run on the same date.

Only the first eligible rule starts when several are due together. Separate their times to run more than one. Timezone changes and processing gaps longer than 90 seconds reset the timing baseline. Daylight saving gaps are skipped. After moving the clock backward, a schedule waits for a date later than its last handled date; it does not repeat a past occurrence.

**Started** confirms that preset application began. Read the final result for confirmed writes, skipped controls and failures. A deleted preset cannot be matched by name to a new preset; edit the schedule to choose the replacement.

Unreadable schedule or occurrence storage pauses scheduling. **Back Up and Reset Schedules** starts an empty schedule library while keeping a local copy of the original data. Presets themselves are retained.

## Keep Displays Awake did not keep a screen on

This control prevents idle display sleep for an explicit 15, 30 or 60 minute session. It does not override closing the lid or manual sleep, reconnect a screen, or light a display that was already off. The session ends on sleep or app quit and is always off at launch. Check the countdown in **Advanced** and start a new session if needed.

If starting fails, the card remains inactive and shows the macOS error. Try **Start** again. If stopping fails, the card retains the active state so you can retry **Stop**; macOS still has an automatic timeout. The app does not need Accessibility or Input Monitoring permission for this feature.

## A screen will not reconnect

If you disabled the MacBook screen using Display Mini and then unplugged the last external screen, the app attempts to restore the MacBook screen automatically with the lid open. Allow a few seconds for macOS to update its display list. The app must still be running. Recovery pauses for a closed lid, sleep, an unreadable lid state, or another active external screen.

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
