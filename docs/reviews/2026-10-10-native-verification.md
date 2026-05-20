# Everyday controls native verification

Date: 2026-10-10. Local build: 0.3.0. Hardware: M1 Pro and LG IPS QHD. Serial numbers, UUIDs and paths are intentionally omitted.

## Observed

* The existing 300-point main panel still exposes both screens, brightness, volume, resolution, recovery, refresh and quit. Mute, Presets and Keyboard Shortcuts are available through accessibility labels.
* LG volume changed from 100% to confirmed 0% with the button, then restored to confirmed 100% on unmute.
* A temporary preset captured built-in brightness 70%, LG brightness 80%, and LG volume 100%.
* Applying that preset completed with an Applied message, after monitor write verification.
* Rename updated the row and survived quitting/relaunching the app. Deleting the temporary preset returned to the empty state.
* The shortcut settings listed all nine actions and showed no registration errors. Everyday shortcuts remained enabled.
* Final monitor levels matched the original values. No resolution or connection changes were made during this verification.

## Limits

Native screenshots from the automation tool captured the main panel but cropped popovers extending beyond its bounds. Popover contents and actions were verified through the accessibility tree. Light/dark appearance changes and physical unplug recovery were not repeated for this feature update.

Synthetic key injection did not produce a hotkey action in this session. A physical keyboard check was requested separately; registration success alone is not evidence of event delivery or physical pointer targeting. The automated store tests cover disabled/busy/missing-target/missing-preset handling without sending monitor commands.

## Editable shortcut follow-up

The key/menu editor was checked in the running app. Brightness up was changed from ⌃⌥⌘↑ to ⌃⌥⇧⌘K using the key menu and Shift checkbox. Save returned to the list with the new binding and no registration error. After quitting and relaunching, the list still showed the custom binding. Reset All to Defaults restored ⌃⌥⌘↑. The test changed no monitor level. Duplicate/conflicting assignments, released IDs, recovery retention and rollback are also covered by the injected-registrar suite. Physical keyboard delivery remains the previously documented separate check.

The follow-up compact menu was also verified in the running app: it opened six category menus, Letters A–M contained 13 keys, and selecting K updated the draft binding. Cancel left the saved default unchanged. The key selector is 120 points wide.

## Keyboard recording follow-up

Implementation commit: `10e5390`. In the native app, Record Shortcut captured injected Control+Shift+K and Save updated Brightness up. Recording the same combination for Brightness down produced the expected duplicate error on Save. Recording the recovery combination showed its keys without running recovery, and Save rejected assignment to Brightness down. The same injected input can follow local AppKit delivery, so this does not establish physical Carbon event delivery.

A bare A showed invalid-input feedback while recording continued and Save remained disabled. Escape stopped listening and preserved the previous draft. Closing the shortcuts popover during recording and reopening it returned to the normal list. The original Brightness up binding was restored through Default and Save. Built-in brightness remained 70%, LG brightness 80%, and LG volume 100%.

Foreground switching could not be reliably exercised by the native automation tool. Automated tests instead install the real local monitor and notification observers, post application/window blur notifications, assert recording stops, and check removed observers no longer react. Physical app focus transitions and physical global hotkey delivery remain distinct manual checks. The independent recording review approved the implementation with no findings.
