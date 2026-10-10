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
