# Final Status Report — March 12, 2026
## Scroll+DMS → Niri+eqsh Migration

### Config Validates Clean
```
niri validate → config is valid
```

---

## Completed

### niri/binds.kdl
- `Mod+Shift+Q` → `close-window` (was `quit niri`)
- `Mod+Q` → removed
- No WM exit binding (intentional)
- `Mod+Shift+F` → `switch-preset-column-width-back` (was marked "dropped" — actually exists in niri)
- `Mod+Shift+G` → `switch-preset-window-height-back` (same)
- All QUICKSHELL TODO placeholders replaced with real script calls
- F1-F10 fully wired

### niri/startup.kdl
- `spawn-at-startup "quickshell" "-p" "~/.config/quickshell/eqsh"` added
- cliphist watchers present (text + image)

### niri/layout.kdl
- `focus-ring { off }` confirmed present

### niri/scripts/ — 23 scripts
9 eqsh IPC wrappers: `spotlight`, `settings`, `control-center`, `dnd`, `brightness`, `media`, `launchpad`, `sigrid`, `eqsh-screenshot`
4 standalone: `volume`, `clipboard`, `powermenu`, `record`
10 from scroll: `swappy`, `screenshot`, `colorpicker`, `battery`, `pomodoro`, `pomo`, `fzf-nmcli`, `fzf-shortcuts`, `wifi-menu.sh`, `music-download`

### quickshell/eqsh/
- Moved from `eqsh/eqsh/` → `quickshell/eqsh/`
- Repo scaffolding removed
- Broken `.qmlls.ini` symlink removed

---

## Fixes Applied During Final Audit

| Fix | Detail |
|-----|--------|
| `fzf-shortcuts` path | Was `~/.config/sway/scripts/shortcuts` → now `$HOME/.config/niri/scripts/shortcuts` |
| WM-MIGRATION.md E4 | Was `doNotDisturb toggle` → now `notificationCenter toggle` (matches actual script) |
| Reverse-cycle bindings | `Mod+Shift+F` and `Mod+Shift+G` restored — `switch-preset-*-back` actions exist in niri |

---

## Known Risks for First Boot

| Risk | Mitigation |
|------|------------|
| quickshell not installed | `dnf copr enable errornointernet/quickshell && dnf install quickshell` |
| eqsh is Hyprland-only | IPC handlers + notifications + OSD work. UI panels using `Quickshell.Hyprland` imports will fail. Enviction confirmed niri port is planned. |
| MacTahoe icon theme missing | eqsh `shell.qml` pragma requires it. Install or edit pragma. |
| rofi theme files missing | powermenu/battery reference `~/.config/rofi/powermenu/powermenu.rasi` etc. Scripts work without theme (rofi falls back to default). |
| `fzf-shortcuts` markdown dir empty | `~/.config/niri/scripts/shortcuts/` doesn't exist yet. Script fails gracefully. |

---

## Not Wired Yet (scripts exist, no binding)

| Script | What it does |
|--------|-------------|
| `launchpad` | eqsh app grid |
| `sigrid` | eqsh AI assistant |
| `eqsh-screenshot` | eqsh screenshot tool |
| `record` | wf-recorder screen recording |

---

## Future Items (from WM-MIGRATION-COMMENTS.md fact-check)

| Item | Status |
|------|--------|
| Reverse-cycle sizing | FIXED — `switch-preset-*-back` now bound |
| `Mod+V` floating conflict | NOT AN ISSUE — we use `Mod+Tab` for floating (like scroll) |
| `niri msg event-stream` for bar indicators | Noted for future script rewrites |
| Named workspaces vs index-based | Worth exploring later |
| `focus-workspace-previous` | Could bind to freed-up key |
| `Mod+Shift+E` Google Drive webapp | Remains dropped — could reassign |

---

## Files Modified/Created

```
MODIFIED:
  niri/binds.kdl          — all quickshell wiring, keybind fixes, reverse-cycle
  niri/startup.kdl        — quickshell spawn added

CREATED (scripts):
  niri/scripts/executable_spotlight
  niri/scripts/executable_settings
  niri/scripts/executable_control-center
  niri/scripts/executable_dnd
  niri/scripts/executable_brightness
  niri/scripts/executable_media
  niri/scripts/executable_launchpad
  niri/scripts/executable_sigrid
  niri/scripts/executable_eqsh-screenshot
  niri/scripts/executable_volume
  niri/scripts/executable_clipboard
  niri/scripts/executable_powermenu
  niri/scripts/executable_record
  niri/scripts/executable_swappy
  niri/scripts/executable_screenshot
  niri/scripts/executable_colorpicker
  niri/scripts/executable_battery
  niri/scripts/executable_pomodoro
  niri/scripts/executable_pomo
  niri/scripts/executable_fzf-nmcli
  niri/scripts/executable_fzf-shortcuts
  niri/scripts/executable_wifi-menu.sh
  niri/scripts/executable_music-download

CREATED (eqsh config):
  quickshell/eqsh/        — full eqsh QML config (moved from eqsh/eqsh/)

CREATED (docs):
  WM-MIGRATION.md
  EQSH-NIRI-PORT.md
  NIRI-BINDS-HANDOFF.md
  FINAL-status-report-claude-march12.md

REMOVED:
  eqsh/                   — repo scaffolding (README, LICENSE, Media/, etc.)
  quickshell/eqsh/.qmlls.ini  — broken runtime symlink
```
