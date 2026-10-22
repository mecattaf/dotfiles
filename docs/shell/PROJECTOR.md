# PROJECTOR: the herdr chapter of SHELL.md

This chapter states how terminals work in Tom's shell: one herdr server on the strix holds every PTY and agent, and every client window is a projector onto it. SHELL.md links here. Labels: TOM (verbatim, dated), REPORTED (a file says so, path given), MEASURED (command given), INFERRED (judgement). Written 2026-10-22 in the shell consolidation dry run. Nothing here was run against herdr, ssh, kitty or Sway.

## 1. One server, on the strix

REPORTED `home/herdr.nix` header, ruling B5: one herdr server, strix only. Every interactive host gets the binary, because the client is how a server is reached. On the strix `herdr` attaches locally; elsewhere `herdr --remote strix` attaches over the tailnet.

REPORTED `home/herdr.nix`, ruling B6: the server unit `herdr.service` is a systemd user unit wanted by `default.target`, deliberately not tied to `graphical-session.target`. PTYs outlive the compositor, a logout and a lid close. Linger on the strix keeps it up with no login session.

REPORTED `home/herdr.nix`, #352 and #354: `OOMPolicy=continue` so one runaway pane child does not stop the server, and `X-SwitchMethod = "keep-old"` so a Nix switch never restarts it. A new herdr version lands only on a deliberate restart.

REPORTED `home/herdr.nix`, ruling B7: `~/.config/herdr` is herdr's runtime directory (socket, session store, `plugins.json`). Only `config.toml` is ours, a single file out of store symlink into the checkout, reloadable with prefix+shift+r. `sway-client.toml` is generated from the same file with `prompt_new_workspace_name = true` added, for new Sway projectors only.

## 2. The client as projector

REPORTED `home/dot_local/bin/herdr-projector`: the projector is `kitty --class herdr-projector -e ~/.local/bin/herdr-projector`, which runs `herdr --remote strix --remote-keybindings server`. The kitty class is how the chord scripts tell a projector from any other kitty.

Why a projector and not `ssh -t strix herdr`: herdr's clipboard image bridge runs only in a `--remote` client, reading the laptop's Wayland clipboard and staging the image on the server (REPORTED, script header citing herdr `src/client/clipboard_images.rs`). Under plain ssh, agents on the strix see no image.

Why `--remote-keybindings server` is mandatory: in `local` mode the client strips its own `[[keys.command]]` bindings and never merges the server's, so the tally popups would do nothing from the laptop (REPORTED, script header and `config.toml`).

Entry points (REPORTED):

| entry | where | what it runs |
| --- | --- | --- |
| `herdr-sway-projector` | any Sway seat | on the strix with `HERDR_SWAY_LOCAL=1`: refuses unless `herdr.service` is active, then `herdr client`; elsewhere `herdr-projector` |
| `herdr-projector` | client | the reconnect loop below |
| `desk` | fish, any host that is not the strix (`home/dot_config/fish/conf.d/remote.fish`) | `exec ~/.local/bin/herdr-projector` |
| `herdr-chord <verb>` | Sway binds | hands off to `herdr-picker --chord <verb>` |

`HERDR_SWAY_LOCAL` and `HERDR_SWAY_SEAT` are set per host in `home/herdr.nix` (REPORTED).

## 3. Chord verbs and the slot policy

Chord verbs (REPORTED `herdr-chord`, `home/dot_config/sway/binds.conf` lines 8 through 11 in the source checkout):

| Sway key | command | verb |
| --- | --- | --- |
| Mod+Return | `herdr-chord new` | a new workspace in a new projector window |
| Mod+Ctrl+Shift+Return | `herdr-chord sidebar` | a new projector with herdr's agents sidebar |
| (unbound on Sway) | `herdr-chord rename` | rename the focused workspace |
| Mod+Ctrl+Space | `herdr-picker` | the Vicinae picker over projectors and parked views |

`herdr-picker` also takes `--workspace new|close|detach|rename|restore` and `--json` for read only rows (REPORTED, `main()`).

Slot policy (REPORTED `herdr-picker` docstring and code): a Sway slot is a numbered workspace 1 through 9 and owns exactly one projector, including while parked in the scratchpad. The slot is recorded as a Sway mark `herdr-slot-N`; labels are `herdr-label-<seat>-slot-N-<hex6>`. Nine slots at most; the tenth request fails with "All nine Herdr slots are occupied or parked". The picker refuses to merge two projectors into one slot and refuses duplicate workspace numbers. Herdr APIs are read only from the picker; focus stays in Sway, and current identity is never inferred from the server's global focus.

INFERRED, from wave1 note 16 section 6 item 2: because `[ui] window_title = ""`, a projector's title carries no workspace, so after a reconnect a projector may show a different herdr workspace than its marks claim. The marks are the only durable slot binding today.

## 4. Reconnect and cleanup seams

Reconnect, #385 seam 1 (REPORTED `herdr-projector`): plain `herdr --remote` exits 1 on a lost link and has no retry. The loop treats exit 0 as a deliberate end (prefix+q, or the window's hangup), exit 2 as a usage error not retried, and anything else as a lost link retried with backoff 1, 2, 5, 10, then every 30 seconds. A session that held for 60 seconds or more resets the backoff. After a reattach the window lands on the server's default target, not necessarily the workspace it showed.

Unit preflight (REPORTED): before every attach one BatchMode ssh asks `systemctl --user is-active herdr.service` on the target. If no server listens, the remote `remote-client-bridge` would spawn an unmanaged daemon that fights the unit over `herdr.sock`; an inactive unit is treated like a lost link. `HERDR_PROJECTOR_UNIT=` (empty) skips the check.

Cleanup, #385 seam 6 (REPORTED): `herdr --remote` installs no signal handler, so a closed kitty window leaves a ControlPersist ssh master `/tmp/herdr-ssh-<pid>-<n>/ctl` and a bridge socket `/tmp/herdr-remote-<pid>-...sock`. The script runs `ssh -O exit` on that master and removes that pid's files on every child exit and on HUP, TERM and INT, and sweeps leftovers of any earlier projector whose pid is no longer a live herdr at start.

Footguns recorded, not fixed (REPORTED `home/herdr.nix`): `herdr --remote` may offer to stop and replace an incompatible server, which kills every pane, so a herdr bump lands on the strix before or with the client; decline any offer to install a non Nix binary into `~/.local/bin/herdr`.

## 5. The prefix and every [keys] entry

REPORTED `home/dot_config/herdr/config.toml`: `prefix = "ctrl+b"`, herdr's default pinned explicitly.

Command keys declared in `[[keys.command]]` (REPORTED, all six):

| key | type | command | purpose |
| --- | --- | --- | --- |
| prefix+t | popup 80 by 60 percent | `tally-steer` | steer this tally lane, taking a 600 second campaign hold first |
| prefix+shift+s | popup 80 by 60 percent | `tally-steer --no-hold` | steer without embargoing the campaign |
| prefix+shift+a | shell | inline script, `tally campaign pardon` | pardon the lane's attempt latch, feedback through `notify-send` |
| prefix+shift+o | popup 90 by 85 percent | inline script, `less +F` on the newest `<uuid>*.out` | the raw lane capture, followed live |
| prefix+i | popup 85 by 70 percent | inline script, `tally campaign inbox --state open --json` | open inbox entries for this lane |
| prefix+shift+v | pane | `tally-lane-view --task <uuid>` | reopen the live trace viewer |

All resolve the lane through `HERDR_ACTIVE_PANE_ID` and the sidecar map `~/.local/state/tally-bridge/panes` (REPORTED). The config says they were verified free against herdr's default map at 0.8.2 (REPORTED; not rechecked against the pinned 0.9.x).

herdr default keys the config relies on, named in its comments (REPORTED, defaults not declared in the file): prefix+q detach, prefix+b sidebar toggle, prefix+w workspace picker, prefix+g session navigator, prefix+shift+n new workspace, prefix+shift+d close workspace, prefix+c new tab, prefix+shift+x close tab, prefix+shift+r reload config, prefix+s settings, prefix+p previous tab, prefix+o open notification target.

INFERRED: KEYMAP.md covers Sway binds; herdr prefix keys live inside the terminal layer and should appear there as a separate table generated from this config. That is proposed, not done in this lane.

## 6. The theme terminal rule

REPORTED `config.toml` `[theme] name = "terminal"` (2026-09-17): every herdr token is an ANSI slot, so kitty paints herdr chrome and panes in whatever theme `~/.local/bin/theme` selected, and repaints live through DEC mode 2031 and an OSC 10, 11, 4 requery. A theme switch never edits this file. Never pick a theme from herdr's settings overlay: it writes `name` and `auto_switch = false` into the tracked file.

## 7. Remote panes: what runs where, what survives what

| thing | runs on | survives |
| --- | --- | --- |
| herdr server, PTYs, agents (claude, codex), fish (`default_shell = /run/current-system/sw/bin/fish`) | strix | compositor restart, logout, client sleep, projector close, Nix switch |
| projector loop and `herdr --remote` client | client, inside kitty | link drops (loop reattaches); not a window close |
| clipboard image bridge | client side `--remote` process | while the projector lives |
| Sway slot marks | client Sway | parking; not a Sway restart (INFERRED, wave1 note 16 section 6 item 3) |

Lifecycle rule (REPORTED `config.toml [session]`, #352 and #355): an explicit exit (Ctrl+C, an agent's `/exit`) closes the pane for good. Closing a projector or prefix+q only detaches. A server restart restores layout, and `resume_agents_on_restore = true` relaunches an agent only where the snapshot carries its session ref; every other pane is a fresh shell in its cwd. `herdr-panes` lists live panes with agent, status and last activity, and `herdr-panes close <id>` ends one on purpose. `herdr-prune-shells` closes workspaces whose every pane is an idle shell (REPORTED, MEASURED by its author 2026-09-11: 99 workspaces, 98 idle). `pane_history` stays off so screen contents never persist to disk.

## 8. GPUIX seam

INFERRED position for the GPUIX phase, with the API shape REPORTED from `/home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/wave1/16-herdr-api-and-scripts.md` (note 16, read only worktree): the shell observes herdr, it never drives it.

1. Door: the server socket `~/.config/herdr/herdr.sock`, newline delimited JSON, one request per connection (note 16 section 5.3, MEASURED by its author). The CLI `herdr <group> <verb>` is the equivalent door.
2. Reads: `session.snapshot` once at bootstrap and after any reconnect, then `events.subscribe`; also `workspace.list`, `agent.list`, `agent.get`, `pane.read`, `pane.process_info`, `ping` (note 16 section 5.5).
3. Writes: none for navigation; focus stays in the compositor. The only writes the scripts issue are `herdr workspace close` and `herdr pane close`.
4. Remote reads from the client: only ssh per read is proven; an `ssh -L` socket forward is INFERRED (note 16 section 6 item 5).
5. Slot identity moves from Sway marks to whatever the GPUIX shell persists; until then marks stay authoritative (note 16 section 6 items 2 and 3).

The projector itself (kitty plus `herdr --remote`) is not ported in the GPUIX phase; the GPUIX rail and switcher replace `herdr-picker`'s Vicinae surface only. That boundary belongs in DEFERRED.md.

## 9. Lint evidence

MEASURED: `tools/shell/shellcheck-bins.sh` (this repo) lints every shell script in `home/dot_local/bin` and writes a Markdown table. The dry run copy is `/home/tom/wednesday-oct21/dryrun/shell/checks/shellcheck-bins.md`: 39 shell files, 30 clean, 0 errors, 14 warnings, 12 info or style notes, and zero findings in all five herdr shell scripts.

## Not verified

No herdr, hk, ssh, kitty or Sway command was run; every runtime claim is REPORTED from comments and code. The herdr default key list comes from config comments, not from the 0.9.x source. The collision free claim for the six command keys dates from 0.8.2. Line numbers in binds.conf refer to the source checkout and may move with lane 12's edits. Note 16 measurements are its author's, not this lane's.

No second reader (Tom's light verification rule, 2026-10-20).
