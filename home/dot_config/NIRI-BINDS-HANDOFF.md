# Niri Binds Handoff

## DONE — Wired into binds.kdl

All of these are live in `niri/binds.kdl` and call scripts from `~/.config/niri/scripts/`.

### Keybinding fixes
- `Mod+Shift+Q` → `close-window` (was `quit`)
- `Mod+Q` → removed
- No WM exit binding (intentional)

### eqsh IPC (via wrapper scripts → `quickshell ipc call`)
| Binding | Script | eqsh target |
|---------|--------|-------------|
| `Mod+Shift+D` | `spotlight` | `spotlight toggle` |
| `Mod+Comma` | `settings` | `settings toggle` |
| `Mod+B` | `control-center` | `controlCenter open` |
| `Mod+O` | `dnd` | `notificationCenter toggle` |
| `F1` | `brightness down` | `display dimmer 5` |
| `F2` | `brightness up` | `display brighter 5` |
| `F3` | `media play` | `music togglePlay` |
| `F4` | `media prev` | `music previous` |
| `F5` | `media next` | `music next` |
| `F9` | `pomodoro menu` | *(standalone, no eqsh)* |
| `F10` | `powermenu` | *(standalone, no eqsh)* |

### Standalone scripts (no eqsh dependency)
| Binding | Script | Backend |
|---------|--------|---------|
| `Mod+V` | `clipboard` | cliphist + rofi |
| `F6` | `volume mute` | wpctl (eqsh OSD auto-reacts) |
| `F7` | `volume down` | wpctl |
| `F8` | `volume up` | wpctl |

### Already wired (unchanged)
- `Mod+A` → `swappy full`
- `Mod+S` → `swappy area`
- `Mod+C` → niri built-in color picker
- `Print` / `Ctrl+Print` / `Alt+Print` → niri built-in screenshots

## TODO — Not yet wired

### eqsh extras (need binding assignment)
| Script | eqsh target | Suggested binding |
|--------|-------------|-------------------|
| `launchpad` | `launchpad toggle` | ? |
| `sigrid` | `sigrid toggle` | ? |
| `eqsh-screenshot` | `screenshot toggle` | ? (or replace niri built-in) |

### Standalone extras
| Script | Notes |
|--------|-------|
| `record start/select/stop` | Screen recording via wf-recorder + niri msg |

### Startup
Add to `niri/startup.kdl`:
```
spawn-at-startup "quickshell" "-p" "~/.config/quickshell/eqsh"
```
