# Display personalization verification

Date: 2026-10-10. Feature implementation: `e3787ab`, with subsequent identity and current-mode guard refinements. Local Apple Silicon build with an LG external screen. No private hardware identifiers are included.

## Native observations

* The existing compact panel exposes a labeled settings button beside each display name.
* Display Settings shows the system name, an empty name editor, a disabled Use System Name action before customization, Star Current Resolution, and a scrollable list of available density/refresh variants.
* Saving the temporary name Desk Screen updated the panel title and accessible labels immediately.
* Starring the current external mode added a 2560 × 1440, Standard, 75 Hz favorite at the top of the resolution menu.
* The name survived Refresh. Both the name and star survived quitting and relaunching the app.
* Use System Name and Unstar Current Resolution restored the original name and empty favorites. No resolution, connection, brightness or volume change was requested. The displayed brightness/volume values remained unchanged.
* Isolated native SwiftUI renders of the settings popover were inspected in light and dark appearances. Both retained readable labels, complete controls and a scrollable resolution region.

## Automated and source checks

Four model scenarios cover trimmed names, control characters, count limits, UUID normalization, independent screens, density and refresh variants, unavailable favorite retention/removal, round trips, and malformed/oversized stored data. Three real store scenarios use isolated defaults and hardware substitutes to check name persistence, stable-identity requirements, stale favorite rejection without recovery-record changes, and explicit backup/reset without modifying unrelated settings.

The full existing test suite and native app build passed. Direct build scripts now compile the expanded DisplayCore module as one object. Documentation links and media dimensions/metadata passed validation. Source review confirmed that favorites re-resolve current identity and modes before entering the unchanged resolution preview/recovery flow, and names never become routing keys or diagnostic report fields.

## Limits

The UI check starred the current mode without applying a different mode. Physical favorite switching, cable changes and unplug recovery were not repeated. Stale/unavailable inputs are covered by model/store tests; those tests do not establish compatibility for other monitors. Light/dark images use isolated sample data and are not live desktop captures.
