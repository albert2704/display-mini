# User guide

## The panel

Click the monitor icon in the menu bar. Each known display has a title row with its name and connection switch. Built in displays show brightness and resolution. External displays also show monitor controls and volume.

Values come from macOS or the monitor. Detection may take a moment. An unavailable control stays disabled instead of displaying a made up measured value. The panel refreshes when screens change, after wake, and when you use Refresh.

## Brightness

**Combined** means hardware brightness and software dimming share one slider:

| Slider range | Result |
| --- | --- |
| 20% through 100% | Hardware brightness scales from its minimum to maximum. |
| Below 20% | Hardware stays at its minimum and a dark overlay adds dimming. |

Built in and Apple displays use DisplayServices, with native brightness clamped above absolute zero. Other supported monitors use DDC/CI. A combined or software percentage is not the monitor's physical backlight percentage, so numbers can differ from the monitor's own menu or another utility.

**Software** means the app darkens the image with an overlay because hardware control is unavailable or software mode was selected. This does not reduce the monitor's backlight setting. The overlay leaves a small nonzero visibility floor. Closing the app removes its overlays.

Writes are briefly debounced to avoid flooding the monitor while dragging. DDC writes are read back before being considered confirmed. A rejected or unconfirmed change displays an error.

## External monitor volume

Volume controls the monitor's speakers through DDC VCP code `0x62`. It does not set Mac speaker volume or change the selected macOS audio output.

macOS still needs the correct audio output, and the cable must carry audio. Brightness support does not guarantee volume support. If the monitor cannot report current volume and a valid maximum, the slider is unavailable.

## Monitor Controls

Open **Monitor Controls…** or **Configure DDC…** on an external display to inspect support.

* **Detect Again** retries capability reads.
* **Use software brightness only** selects overlay dimming even when hardware brightness is available.
* Communication errors appear in this panel.

Enable DDC/CI through the monitor's physical controls and on screen menu. Display Mini cannot enable it in firmware that blocks communication. Try a direct cable when a dock or adapter blocks DDC; no particular port guarantees support on every monitor.

## Resolution

The slider provides one stop per logical size. The resolution label opens the full list, including density and refresh variants reported by macOS.

The slider tries to preserve current density and refresh rate when selecting another size. HiDPI modes use more physical pixels than the logical desktop size. Display Mini does not manufacture unsupported resolutions or create virtual displays.

Releasing the slider or selecting a mode starts a preview with **Keep** and **Revert**. The app attempts to restore the previous mode after 15 seconds unless you keep it. Keep saves the mode through macOS display configuration.

Only one preview is active at a time. If a display disappears or rollback fails, the recovery record is retained. Reconnect the screen and use **Revert** or **Restore Displays**. After a restart, unresolved recovery can be explicitly dismissed with **Keep current resolution** when shown.

## Connection switches

Turning a display off disconnects it from the macOS desktop. Windows can move to the remaining display. This is connection management, not merely drawing a black window or sending a physical monitor power command.

The last active display cannot be disconnected. An owned disconnected screen remains listed for reconnection. Availability depends on the private macOS connection API and display path.

macOS may stop returning a UUID for a disconnected screen. The app retains its vendor, model, and serial identity and checks current display IDs. If the match is ambiguous, it does not guess which screen to operate.

## Footer and recovery

| Button | Action |
| --- | --- |
| Curved arrow | Restore screens and pending changes owned by Display Mini. |
| Circular arrow | Refresh discovery and control values. |
| Power icon | Quit the app. |

**Control + Option + Command + R** performs recovery and opens the panel. Recovery attempts to reconnect owned disconnections, roll back a pending mode, remove dimming, and raise displays in the lowest brightness range to a readable level.

Recovery is best effort. A physically unplugged monitor must be reattached. Ambiguous identity, a removed mode, or a changed private API may require macOS Displays settings, cable reconnection, or logging out. Read the error before dismissing recovery information.

## Scope

The preview has no brightness/volume media key remapping, automatic updates, DDC power-off command, rotation, mirroring configuration, virtual displays, or scheduling. It focuses on the controls above.
