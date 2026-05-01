# Display Mini

Source: user supplied BetterDisplay screenshot.

Character: compact macOS utility, translucent surfaces, rounded title strips, restrained blue accents, quiet secondary labels and native SF symbols. Tokens live in `Sources/DisplayMini/PanelView.swift` in `PanelStyle`.

## Build mandate

Each display appears in one card, headed by its name, display icon, and connection switch. Brightness comes first, volume only for external displays, then resolution. DDC configuration is a compact blue affordance. The panel is 300 points wide and scrolls when several displays are present. A small footer provides recovery, refresh and quit. No marketing page, oversized branding, unrelated display features, or synthetic monitor data in the normal app.

Use the system font and native accessibility for all controls. Material follows the user's macOS appearance. Keep labels legible in both appearances. Long display names truncate; accessible labels retain the full name.
