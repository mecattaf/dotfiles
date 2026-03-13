# Niri Config — Validation & Polish (2026-03-13)

Full audit of all keybindings (sections A–I of the migration checklist) confirmed correct. The following changes address gaps, UX issues, and missing config identified during validation.

## Keybind changes (binds.kdl)

### Consume/expel swapped with move-column
- `Mod+Shift+H/L` now does `consume-or-expel-window-left/right` (was `move-column-left/right`)
- `Mod+Alt+H/L` now does `move-column-left/right` (was `consume-or-expel-window-left/right`)

### Overview on Page keys
- `Mod+Page_Up` and `Mod+Page_Down` both trigger `toggle-overview` (replaced the unimplemented gap adjustment TODO)

### Workspace up binding added
- `Mod+Shift+U` → `focus-workspace-up` (previously only `Mod+U` for down existed)

## Animations (misc.kdl)

Ported scroll animation curves to niri's animation system:
- General movement (workspace-switch, horizontal-view-movement, window-movement, window-resize, config-notification): 120ms with cubic-bezier(0.25, 0.1, 0.25, 1.0)
- Window open/close: 100ms with cubic-bezier(0.3, 0.0, 0.7, 1.0)

Requires niri 25.08+ for cubic-bezier support.

## Hotkey overlay (misc.kdl)

- Added `skip-at-startup` so the overlay no longer appears on every login
- Still accessible via `Mod+Slash`

## Overview & gestures (misc.kdl)

- `overview { backdrop-color "#000000" }` — black backdrop for overview mode
- `gestures { hot-corners { off } }` — disabled hot corners

## Kanshi startup delay (startup.kdl)

- Changed `spawn-at-startup "kanshi"` to `spawn-at-startup "sh" "-c" "sleep 0.5 && kanshi"`
- Prevents screen flash on login caused by kanshi re-applying output profiles before niri finishes initializing
