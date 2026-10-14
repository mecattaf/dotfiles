# Top-display Sway workspace switcher

`Mod+i` runs `~/.local/bin/sway-workspace-switcher --output eDP-1` (binds.conf).
A second `Mod+i` closes only this switcher's own Fuzzel menu, through a private
Unix socket keyed by `SWAYSOCK`. Escape cancels; typing filters; Enter chooses a
row. No new service, timer, compositor or Herdr server mutation.

The target is the **actual active eDP-1 output**, the upper panel of kanshi's
Duo profile. Live membership outranks binds.conf's assignment: the rows are
slots 1 to 9 plus whatever else sits on eDP-1 now, minus any number that sits on
another output or is ambiguous. On 2026-10-14 at 02:21 that read 1, 2, 3, 6, 7,
8, 9, 10 (10 had been moved to the top; 4 and 5 sat on eDP-2 and were left out).
Empty slots open by number; existing workspaces are selected by their complete
name (`workspace "10"`). Nothing on the lower display is moved. If eDP-1 is
absent the command fails visibly instead of falling back to another display.

Herdr status is sampled once at open through `herdr-picker`'s read-only
`remote_snapshot()` and the same identity rules as the picker: a live title
match first, else the slot's label or workspace mark, shown as `assigned
<status>`. Unknown and unavailable states never become idle, and nothing is
inferred from Herdr's global focus. The switcher never calls a focus verb on
Herdr; focus stays in Sway.

Fuzzel is an ordinary native layer-shell client added to the physical seat
beside Vicinae (decision 4 of the convergence soak). It targets the output
explicitly, so opening the menu does not focus or rearrange the lower panel.
Colours come from `~/.config/theme/desktop-shell.json` when a generation ships
one, else from the shipped `~/.config/theme/kitty.conf`, parsed as data (never
sourced). Main's generations ship only the kitty fragment.

`herdr-picker` gained two Sway-only helpers for this: `select_workspace(number,
name=None)` and `hyprland()` (always `False`). The switcher stops with
`AttributeError` on its first call without them.

## Validation

```sh
runtime-test -- python3 -m unittest discover -s tests/workspace-switcher -v
runtime-test -- python3 tests/workspace-switcher/smoke.py [--evidence DIR]
nix build .#checks.x86_64-linux.herdr-launchers
```

`test_switcher.py`: Codex's sixteen fixture tests (actual-output inclusion and
exclusion, Herdr attribution, assigned and unavailable states, stale-selection
guards, parked process identity, menu isolation between compositors, toggling,
exact output and theme arguments) plus the kitty-fragment palette fallback.

`test_fixtures.py`: the Zenbook's `get_workspaces`, `get_tree` and `get_outputs`
captured at 02:21 on 2026-10-14 (`fixtures/zenbook-0221-*.json`; eDP-1 holds 1,
2, 3, 6, 8, 9, 10; eDP-2 holds 4, 5; projectors on 1, 2, 3, 10, 4 with marks
`herdr-slot-{1,2,3,5,4}` and labels `client-slot-4-9690f0`, `client-slot-2-d6929b`,
`client-slot-3-02c703`, `client-slot-5-fc4d18`, `client-slot-4-6a3fb5`; Chrome
windows on 5, 6, 8, 9). Expected rows 1, 2, 3, 6, 7, 8, 9, 10 with 1, 2, 3, 10
reading `assigned <status>`. A second fixture holds binds.conf's layout (1 to 9
top, 10 bottom, rows 1 to 9) and a test pins that the two disagree, so a
config-only reading cannot pass alone. Two tests pin `workspace "10"` for an
existing workspace and `workspace number 7` (and 6) for an empty slot.

`smoke.py`: two headless Sway outputs (`WLR_RENDERER=pixman`), the real Fuzzel
from the Nix store, a stub `herdr` whose snapshot carries the five live labels,
kitty windows standing in for the five projectors (marked as on the live seat)
and for the Chrome windows on 5, 8 and 9. It checks the seat (1, 2, 3, 8, 9, 10
top; 4, 5 bottom; 5 focused), the `--json` rows and their `assigned <status>`
labels, a real `Mod+i` opening the menu on the top output while the bottom is
focused with the bottom's pixels unchanged, the toggle, selecting 10 by name
without moving 4 or 5, opening the empty slot 7 by number on the top output,
and Escape. A persistent virtual keyboard (`wtype -s`) is required because the
isolated seat has no hardware keyboard. Run it only through `runtime-test`.

Evidence from the night it landed: `~/today/2026-10-14-convergence-soak/build/evidence/track8/`.
Physical-seat staging (a Sway reload on the Zenbook) is a separate step on
Tom's word; nothing here reloads, deploys or binds anything live.
