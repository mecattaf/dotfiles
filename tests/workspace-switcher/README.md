# Top-display Sway workspace switcher

`Mod+i` invokes `~/.local/bin/sway-workspace-switcher --output eDP-1`.
A second invocation closes only this switcher's own Fuzzel menu through a private
Unix socket. Escape cancels; typing filters; Enter chooses a row. There is no new
service, timer, compositor, or Herdr server mutation.

The target is the **actual active eDP-1 output**, the upper panel in Kanshi's Duo
profile. Current assignments take precedence over the intended keybinding layout:
workspace 10 belongs in the list when it currently occupies eDP-1; workspace 4
is excluded when on eDP-2. Empty numbered slots 1–9 can be opened on the target.
No lower-display workspace is moved. If eDP-1 is absent, the command fails visibly
instead of falling back to a different display.

Herdr status is sampled when opening, using the same read-only snapshot and live
projector-title identity rules as `herdr-picker`. A mapped projector's actual
containing workspace overrides old slot marks. Parked projectors use their slot
metadata and are identity-checked before reopening. An inferred assigned status
is explicitly labelled `assigned`; unavailable/unknown states never become idle.
No status is inferred from Herdr's global focus. Ordinary workspaces remain usable
when Herdr is unreachable. Workspace output/name and parked PID/app identity are
revalidated before the selected action.

Fuzzel is an ordinary native Wayland layer-shell client, added only for a physical
Sway configuration. It targets the output explicitly, so opening the menu does not
first focus or rearrange the lower panel. Anthropic Sans and the active
`theme/desktop-shell.json` palette are used. On older generations, the existing
`theme/kitty.conf` color values are parsed as data. This is a compact functional
menu; the separate Claude/Primer browser study is the richer design mockup.

Validation:

```sh
runtime-test -- python -m unittest discover -s tests/workspace-switcher -v
runtime-test -- python tests/workspace-switcher/smoke.py
```

16 fixture tests cover actual-output inclusion/exclusion, Herdr attribution,
assigned/unavailable states, stale selection guards, parked process identity,
menu isolation between compositor instances, toggling, and exact output/theme
arguments. The integration smoke uses two isolated headless Sway outputs and the
real Fuzzel binary; its Herdr snapshot is a read-only stub. A persistent virtual
keyboard is required because isolated headless Sway has no hardware keyboard.
The smoke's binary paths pin the package versions available in this checkout's
build environment.

Successful integration evidence: `/tmp/sway-switcher-smoke-14fqrsj_`.
Actual Mod+i opens and closes the menu; reopening, keyboard selection and Escape
work. The menu rendered only on HEADLESS-1 while HEADLESS-2 was focused. The lower
output's screenshots were pixel-identical before/during the menu; workspace 10
was selected without moving lower workspace 4. Logs and screenshots are retained.
This proves the isolated Sway/Fuzzel path; physical-seat staging is a separate
root-coordinated step. No compositor reload, service restart or deployment was
performed by this implementation task.
