# 0004. Display personalization

**Date**: 2026-10-10
**Status**: In Progress

## Summary

Add custom screen names and favorite resolutions. The user requested more features and asked for alternatives to automation, monitor controls, and scroll controls. This slice follows the existing compact SwiftUI design and local preferences model.

## Requirements

* AC-1: Each screen offers a Display Settings popover. Save a trimmed custom name of up to 40 characters, or restore the name supplied by macOS. Empty input restores the system name. Reject control characters and longer names. Labels update immediately and survive relaunch and reconnect using the display UUID. Names never affect hardware routing.
* AC-2: Star the current resolution or any currently available resolution in Display Settings. Store up to 32 favorites per screen. Removing a favorite never changes the current mode. Keep saved favorites when temporarily unavailable, show their unavailable state, and allow removal.
* AC-3: Show available favorites above the full resolution menu. Resolve a favorite against freshly discovered modes by logical dimensions, pixel dimensions, and refresh rate rounded to millihertz. Never persist or replay a native mode ID. Distinguish standard density, HiDPI, and refresh variants. Deduplicate equivalent favorites in the menu.
* AC-4: Selecting a favorite calls the existing resolution preview, guards, recovery record, and 15 second Keep/Revert flow. Saving names or stars performs no hardware write. Hotplug and busy states cannot apply a stale favorite.
* AC-5: Validate schema, UUIDs, names, dimensions, refresh rates, duplicates, size and count before loading local data. Preserve unreadable data and expose an explicit Back Up and Reset action. A reset clears personalization only. Diagnostic reports continue to omit display names and identifiers.

## Decision and design

Extend the existing implementation in place, with no dependencies or permissions. A separate Codable schema 1 document in UserDefaults, key `displayPersonalization`, maps canonical display UUIDs to an optional custom name and an ordered list of favorite resolution descriptors. Limit the document to 1 MiB and 64 displays. An empty entry is removed. Duplicate labels are allowed because routing uses UUIDs.

Keep the native name separately on DisplayDevice and expose the custom name through its existing published name. Refresh updates the native name and reapplies the alias. Preset labels prefer the current display name or saved alias and fall back to the preset's stored name.

Add an accessible settings button beside each card title. Its 360 point popover contains the system name, custom name editor, Save Name and Use System Name actions, a star current resolution action, saved favorites with availability and remove controls, and a scrollable list of available modes to star. Use existing system fonts, SF Symbols, blue accent, native light/dark appearance, and explicit empty/error states.

| Value | Source |
| --- | --- |
| Screen identity | Existing display UUID, canonicalized only for preference lookup |
| System name | Existing built in label or NSScreen.localizedName |
| Custom name | User input after trimming and validation |
| Favorite identity | CGDisplayMode width, height, pixelWidth, pixelHeight and refreshRate rounded to millihertz |
| Current favorite state | Current discovered mode descriptor matched against saved descriptors |
| Available favorite | Exact descriptor match in the device's current mode list while connected |
| Missing favorite label | Its saved dimensions, density and refresh descriptor |
| Selected mode | Current discovered DisplayMode passed to existing changeResolution |

## Build plan

- [x] Add validated personalization storage and regression checks for malformed data, independent displays, limits and mode identity.
- [x] Connect storage to display names and favorites, preserving routing and resolution recovery; test persistence and unreadable data recovery.
- [x] Build the settings popover and favorite resolution menu using the current design system.
- [x] Build and test, inspect native UI states, and update documentation.
- [ ] Publish a PR with regular commits.

## Consequences

Names and favorites belong to this Mac and display UUID. A connection that changes UUID will not inherit another screen's settings. Unavailable favorites remain saved until removed. Favorite names describe geometry and refresh rather than arbitrary labels. Existing presets retain their stored names as a fallback when no current name is available. This feature does not change display arrangement, rotation, or monitor capabilities.

## Rationale

Adding metadata around existing discovery and preview code keeps the change small and preserves recovery. Persisted mode IDs would be simpler but are unsuitable across rediscovery, so saved descriptors are resolved only against current modes.
