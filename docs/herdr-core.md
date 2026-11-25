# hc on the NAS

hc (`herdr-core`, github.com/herdrdev/herdr-core, Apache-2.0) is the terminal
runtime that carries Tom's Mod+Enter stations and the floor's workers on the
brain host. One core per machine, in the default session, listening at
`/run/user/1000/herdr-core/default.sock`. Herdr v1 (`herdr.service`,
`home/herdr.nix`) is a separate program and is not changed by any of this.

## What is declared

| Where | What | Hosts |
|---|---|---|
| `home/herdr.nix` | the `hc` and `herdr-core` package, `pkgs.llm-agents.herdr-core` | every host |
| `home/herdr-core.nix` | `hc-core.service` and the `~/.config/herdr-core/config.toml` link | brain (NAS) |
| `home/dot_config/herdr-core/config.toml` | the config: fish login shell, `notes = true`, `draft_wait = 60`, `headless = "120x40"`, no `socket` | brain |
| `modules/herdr-core.nix` | `kitty.terminfo` system-wide, so `xterm-kitty` resolves for every terminal | brain |
| `home/dot_local/bin/hc-restart-clean` | restart the core from a clean environment after an upgrade | linked everywhere, meant for the NAS |
| `tests/hc-core/` | eval asserts (`checks.hc-core`) and `smoke.sh` against a private core | |

`hc-core.service` is a oneshot: `herdr-core server start` from the user
manager's environment, minus the per-launch names a Claude Code or DSH shell may
have imported (`CLAUDECODE`, `CLAUDE_CODE_*`, `CODEX_THREAD_ID`, `DSH_*`,
`CLOUDFLARE_API_TOKEN`) and hc's own selectors (`HC_SESSION`, `HC_SOCKET`,
`HC_TERMINAL_*`). It then stays "active (exited)". The core and the holder run in
hc's own transient units (`hc-serve-<hex>`, `hc-hold-<hex>`, guarded by
`hc-shutdown-<hash>`), which supervise them: the holder owns every PTY and
respawns a crashed core after 3 s. The unit has no `Restart`, no `ExecStop`, no
`Environment`, and `KillMode=process`, so stopping or restarting it ends
nothing. It is wanted by `default.target` (linger keeps it up with no login)
and carries `X-SwitchMethod=keep-old`.

The config file is a single-file raw link into `~/mecattaf/dotfiles`, like
Herdr's: hc reads its keys per use, so an edit takes effect at the next spawn,
attach or note, with no rebuild and no restart. `~/.config/herdr-core/` stays a
real directory.

## Start, upgrade, stop

- **Start.** `systemctl --user start hc-core.service` (or the next boot). With a
  core already answering on `default.sock` it is a status call and changes
  nothing. A switch that adds the unit starts it once: sd-switch (0.6.3 on the
  NAS, 0.6.4 elsewhere) starts every inactive unit wanted by an active target
  unless it is `stop-only`, and `keep-old` does not prevent that first start.
  After that, `keep-old` means a switch never re-runs it.
- **Check.** `/etc/profiles/per-user/tom/bin/herdr-core server status --json`
  (version, `installed_by: nix`, live terminals); `systemctl --user list-units
  'hc-*'` (one `hc-serve-*`, a `hc-hold-*` once a terminal exists). The core's
  environment, names only: `herdr-core exec env | cut -d= -f1 | sort`.
- **Upgrade** after a fleet switch moved the package: from a plain ssh shell on
  the NAS, outside any hc terminal, run `hc-restart-clean`. It runs the new
  binary's `server restart --fresh` with only `PATH` (fixed), `HOME`, `USER`,
  `LOGNAME`, `SHELL`, `LANG`, `XDG_RUNTIME_DIR` and the NixOS pointers
  `LOCALE_ARCHIVE`, `TERMINFO_DIRS`, `TZDIR`. Programs keep running: the old
  holder drains with its terminals, new terminals go to a new-build holder.
  `systemctl --user restart hc-core.service` does not upgrade a running core.
  Keep the old store path alive until its holder has drained, or a later crash
  of that holder's core cannot be respawned (inferred, not measured).
- **Stop everything** (every program ends): `herdr-core server stop`, typed by
  a person, after `herdr-core ls` shows nothing anyone needs.

## The never-list

- No `hc update`, `hc machine update` or `hc machine add --install`: they copy
  a binary to `~/.local/bin/herdr-core` and restart the core from it, off the
  Nix pin.
- No unit wrapping `herdr-core serve`, and no `Restart=` on a core unit: `serve`
  exits 0 when another core holds the lock, and a restarting unit fights
  `hc server restart` and the holder's own respawn.
- No `hc server start` or `restart` typed inside a Claude Code session against
  the live runtime: a core started there gives that session's variables and
  tokens to every terminal. A bare autostarting `hc` command where no core runs
  does the same.
- No second core and no `HC_SESSION` outside tests. Tests use a private core
  under `~/.local/bin/runtime-test` (`tests/hc-core/smoke.sh`).
- No template named like a binary in `~/.config/herdr-core/templates/` (it
  shadows that binary for every caller). Dotfiles installs none.
- Bare `hc` on the NAS is the hand-installed 0.1.21 in `~/bin` until the
  cutover; use `/etc/profiles/per-user/tom/bin/herdr-core` by absolute path.

## How Mod+Enter uses it

Domicile's Mod+Enter on the Zenbook opens Kitty with `domicile-terminal`, which
keeps today's ssh to the NAS and changes only the remote command: it runs
`~/.local/bin/hc-station new`, which asks this core for a new terminal in `~`
(`terminal.run`, labels `owner=tom ui=kitty seat=zenbook kind=shell`, Kitty's
identity when `xterm-kitty` resolves) and becomes `herdr-core attach` on it.
`ctrl+\` or closing the window detaches; the shell keeps running on the NAS;
`exit` ends it. hc-station never autostarts a core: with no socket it starts
`hc-core.service` once, and if hc is still unavailable it opens a plain fish
with a one-line banner, so Tom always gets a terminal. (hc-station and
domicile-terminal are their own files; see their headers.)

## What is retired

The NAS cutover that follows the switch landing this file (planned for the
night of 25 to 26 Nov 2026; its receipt says whether it ran) retires:

- the two hand-started 0.1.21 cores (`hc-serve-*` from
  `~/.local/share/herdr-core/0.1.21/`: the default session, and the `kitty-hc`
  session from the 19 Nov qualification), both empty, stopped;
- `~/bin/hc`, `~/bin/herdr-core` and `~/bin/hc-kitty`, moved to
  `~/.local/share/herdr-core/retired-20261126/`;
- the hand-written `~/.config/herdr-core/config.toml` (it has `notes = false`,
  `headless = "80x24"`), moved there before the switch, so Home Manager's link
  needs no backup file.

Left for Tom: `~/.local/share/herdr-core/0.1.21/`,
`~/.local/state/herdr-core/kitty-hc/` and `~/.config/herdr-core/pulse-client.conf`.

## Still unverified

- `headless = "120x40"` is the Zenbook window size from the 21 Nov notes; the
  desk check (`stty size` in Tom's usual window) is owed.
- The unit under the real user manager (core and holder moving into their own
  `hc-*` units, the core's environment names) is checked at the cutover, not by
  the smoke, which runs without a user manager.
