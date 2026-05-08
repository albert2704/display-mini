# Architecture

## Runtime layout

```mermaid
flowchart TD
  Status[AppKit status item and recovery hotkey] --> Panel[SwiftUI panel]
  Panel --> Store[DisplayStore on the main actor]
  Store --> Native[NativeDisplays]
  Store --> DDC[Serial DDCClient queue]
  Store --> Dim[DimmingWindows]
  Native --> CG[CoreGraphics display configuration]
  Native --> DS[DisplayServices brightness]
  Native --> SL[SkyLight connection management]
  DDC --> Helper[Bundled m1ddc process]
  Helper --> IO[IOAVService / I2C monitor transport]
  Store --> Prefs[Local UserDefaults recovery records]
```

No server, network request, account, or external runtime is involved. The app is an accessory application with a status item rather than a Dock window.

## Source map

| File | Responsibility |
| --- | --- |
| `Sources/DisplayMini/AppMain.swift` | App lifecycle, status item, popover, duplicate instance handling, global recovery shortcut. |
| `Sources/DisplayMini/PanelView.swift` | Display cards, control bindings, DDC settings, resolution confirmation, footer. |
| `Sources/DisplayMini/CompactSlider.swift` | Native NSSlider tracking, custom drawing, keyboard accessibility, release callbacks. |
| `Sources/DisplayMini/DisplayStore.swift` | Observable device state, discovery, debounce, operation revisions, recovery, and persistence. |
| `Sources/DisplayMini/Hardware.swift` | CoreGraphics/private API adapters and overlay windows. |
| `Sources/DisplayMini/DDCClient.swift` | Serial monitor operations, bounded subprocess output collection, structured probe and write verification. |
| `Sources/DisplayCore/ControlMath.swift` | Brightness math, typed DDC probe validation, diagnostic field allowlist, mode choice, and hardware identity matching. |
| `Tests/DisplayCoreTests/ControlTests.swift` | A small standalone assertion runner, not XCTest. |
| `Vendor/` | Pinned m1ddc source, MIT license, and locally documented transport fixes. |

## Display discovery and identity

SkyLight's `SLSGetDisplayList` or `CGSGetDisplayList` can include disconnected screens. CoreGraphics online discovery is the fallback. Unknown offline slots are hidden from the panel. NSScreen supplies live display names, and CoreGraphics supplies state, UUIDs, modes, vendor, model, and serial values.

A stable UUID identifies a device in the app. When macOS omits that UUID after disconnection, the saved hardware identity is matched against the fresh private list. Fallback candidates must lack a current UUID, preventing a different identified monitor from receiving an old screen's recovery operation. Multiple matching identities are rejected.

Display IDs are transient. Do not hardcode them, assume list order is stable, or use the first monitor as a substitute for the requested screen.

The DDC helper enumerates up to 64 online CoreGraphics IDs. Metadata is optional and initialized before use. It dynamically resolves `IOAVServiceCopyEDID`, validates each external service's EDID header and base block checksum, and matches vendor/model/serial to the requested screen. Uniqueness is checked against all online IDs, including screens without registry metadata. Multiple matching services or duplicate identities are rejected. The framebuffer and DCP proxy need not share a subtree. MCDP29xx keeps its existing 0xB7 address; other matched services use 0x37.

## Brightness and volume

Brightness for built in and Apple vendor displays dynamically resolves `DisplayServicesGetBrightness` and `DisplayServicesSetBrightness`. Other supported external displays use DDC luminance (`0x10`). Volume uses DDC `0x62`.

Combined brightness reserves a threshold of 0.2:

* At or above the threshold, hardware fraction is `(value - 0.2) / 0.8` and software fraction is 1.
* Below it, hardware is at minimum and software fraction is `max(0.03, value / 0.2)`.
* The native hardware write has a 0.01 floor. Pure software mode uses a 0.03 visibility floor.

Software dimming is a black borderless NSWindow on each screen. It ignores mouse events, joins spaces, and sits below the status bar level. Removing the overlay restores the underlying image; it does not undo a physical backlight change.

DDC processes run on a serial background queue. The helper is addressed by display UUID and receives arguments as an array, never a shell command. Each process has a three second timeout followed by bounded termination. The helper performs three bounded read attempts. A valid response must pass envelope, control, status, and checksum checks. The app requires a positive maximum and scales writes to that range. A successful write is read back before confirmation.

Slider work is debounced by 120 ms. Separate brightness and volume revisions prevent one slider from invalidating the other. Lifecycle/recovery invalidation prevents stale completions from reapplying dimming. UI state changes return to the main actor.

Detection uses one schema-versioned JSON `probe` process for both controls, taking current and maximum from the same reply. The app validates the returned UUID, timing, route consistency, attempts and numeric range before accepting it. Unsupported VCP responses are distinguished from invalid replies, I/O failures and unavailable routes. Standard waits 50 ms before reading; Slow waits 150 ms. The selected profile also applies to write confirmation.

Subprocess output is read through a nonblocking pipe and limited to 64 KiB. A deadline covers process execution and EOF collection, including a child retaining an inherited descriptor. There is no detached blocking reader. Diagnostic reports are assembled from explicitly allowed fields, never raw helper output or identity metadata.

## Resolution transactions

CoreGraphics supplies modes. The app filters for desktop usability and minimum logical dimensions, retains the current mode, and creates one slider choice per logical size. The full menu retains available density and refresh variants.

Preview uses a display configuration transaction with session scope. A common run loop timer counts down from 15 seconds. Keep reapplies with permanent scope; Revert reapplies the original mode. An original-mode recovery record is saved before changing the screen. Failed recovery retains that record, and a later preview must not silently overwrite it.

## Connection transactions

SkyLight's `SLSConfigureDisplayEnabled` or `CGSConfigureDisplayEnabled` is resolved at runtime and called inside a CoreGraphics configuration transaction. The app checks that another active display remains before disconnection, records ownership before changing it, and verifies online state after the change.

A switch changes desktop membership, not the DDC physical power state. Recovery and shutdown reconnect only owned disconnections. Screen changes and wake schedule a debounced refresh.

Before refreshing, the store checks fresh OS connection state for a built in panel in `ownedDisconnects`. If no online, active external screen remains and IOPMrootDomain reports an open lid (`AppleClamshellState == false`), it attempts to reconnect that panel. Sleep and in flight connection transactions suppress the attempt. A two second timer runs only while the store retains an owned built in disconnection, covering missed AppKit notifications and temporary missing IDs. Attempts are spaced at least two seconds apart; normal DDC reads are not polled by this timer. Ownership is removed only after the panel is online and active. Shutdown invalidates the timer and suppresses queued recovery work. Synthetic tests cover unplug transitions, another remaining monitor, successful activation, lid state, sleep, ownership and transaction guards.

## Stored data

Domain: `dev.albert.DisplayMini` in local UserDefaults.

| Key | Contents | Purpose |
| --- | --- | --- |
| `displayIdentities` | JSON map of UUID to display ID, vendor, model, serial. | Match disconnected devices when macOS omits UUID. |
| `ownedDisconnects` | Array of display UUIDs. | Retry reconnection on recovery or next launch. |
| `forceSoftware.<UUID>` | Boolean. | Per-display brightness preference. |
| `ddcTiming.<UUID>` | `standard` or `slow`. | Per-display response timing; unknown values use Standard. |
| `software.<UUID>` | Fraction. | Per-display dimming state. |
| `resolutionRecovery` | UUID and previous mode ID, logical size, pixel width, refresh. | Recover an unconfirmed mode after failure or restart. |

The app does not upload these records. Monitor serials and UUIDs can identify local hardware and should be redacted from public reports. Synthetic values are used in tests.

## Boundaries and limitations

CoreGraphics configuration is public API; DisplayServices brightness and SkyLight connection calls are private. The helper uses private IOAVService transport and CoreDisplay information. Dynamic lookup handles some missing symbols but cannot guarantee future OS compatibility.

Hosted tests cannot prove physical DDC or connection behavior. Recovery is best effort and depends on the OS still exposing the display and mode. The release is locally signed and is not an App Store or notarized distribution.
