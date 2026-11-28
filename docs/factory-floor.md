# factory-floor.service

The factory floor (`agency`, repository `github.com/agency-agency/agency`) is a
Cordis orchestrator on herdr-core. It replaces the retired dshd instance `floor`
(2026-11-26). The repository owns the unit: `home/factory-floor.nix` imports its
Home Manager module (flake input `agency`, pinned by rev in `flake.nix`) and sets
only what is this host's. The unit runs in store mode: its ExecStart is a store
launcher that execs the package's `bin/agency-service`, and nothing is built in a
checkout. Checks: `checks.factory-floor` (`tests/factory-floor`).

Until 2026-11-28 the unit ran `~/mecattaf/factory-floor/bin/agency-service` from a
hand-built checkout (option `package = null`). That repository and its checkout
are no longer read by the unit; leave them in place for the rollback below.

## What is declared

| Item | Value on the NAS |
|---|---|
| Unit | `factory-floor.service` (user), `Type=exec`, `Restart=on-failure`, `RestartSec=15`, `UMask=0077`, `KillSignal=SIGTERM`, `TimeoutStopSec=60`, `StartLimitIntervalSec=600`, `StartLimitBurst=10`, `RestartPreventExitStatus=78` |
| Ordering | `After=network-online.target hc-core.service`, `Wants=hc-core.service` |
| Condition | `ConditionPathExists=<package>/bin/agency-service` |
| Switch | `X-SwitchMethod=keep-old`: a switch never restarts a running floor |
| Install | none: wanted by no target, so it never starts at boot or at switch (`autostart = false`) |
| ExecStart | the store launcher `factory-floor-service --patch <overlay>` |
| Profile | the launcher rewrites `~/.local/state/factory-floor/profiles/floor/package.json` before every start: `@agency/bundle-core`, `@factory-floor/bundle-base`, `-bundle-web`, `-bundle-chat` |
| Overlay | `source-scheduled` disabled: the heartbeat's inbox is not consumed (see the flips) |
| Heartbeat wake | off (`heartbeatWake = false`, `floorUnit = null`) |
| Commands | `agency`, `agency-service`, `floor-say` on PATH (the module's `installPackage`) |

The paths are the ones the old unit had: state `~/.agency/state/master/factory-floor`,
work `~/.local/state/factory-floor`, config `~/.config/agency/factory-floor/floor.jsonc`
(host-local, outside this repository), panel `127.0.0.1:3082`. The switch moves the
program, not the data.

## The contract with the agency repository

1. **Entry.** `agency-service` maps the unit's `FACTORY_FLOOR_*` environment onto
   the floor's names and execs `agency serve --profile floor`. It exits 78
   (`RestartPreventExitStatus`) when `floor.jsonc` is missing, and the floor
   exits 78 when `floor.jsonc` does not parse or holds a key it no longer
   takes (a recipe's `maxWorkers`, a `standing` entry with role `brain`), or
   when the profile's `orchestrator` row names `admission`.
2. **PATH.** `node` and the fleet's `herdr-core` first, then
   `/run/current-system/sw/bin`. The floor drops `/nix/store` entries from the
   PATH of its workers, so a recipe names absolute programs. A recipe's
   `AGENCY_BIN` should be `/etc/profiles/per-user/tom/bin/agency`.
3. **hc.** The declared core on the default socket
   (`$XDG_RUNTIME_DIR/herdr-core/default.sock`); the floor never starts a core.
   Workers live in hc's own holder units, so stopping or restarting the floor
   ends no agent, and a restarted floor adopts them.
4. **Environment.** The unit unsets the same per-launch names as
   `hc-core.service` (`CLAUDECODE`, `CLAUDE_CODE_*`, `DSH_*`, `HC_SESSION`, ...).
5. **Scheduled inbox.** The floor's scheduled Source reads
   `~/.agency/state/master/inbox/scheduled`: the heartbeat's real inbox
   (`journal-day`, `fleet-update`, `chats`). It is off here until Tom flips it.
6. **Intent.** The floor's Intent Source reads `.agency/intent/` of every
   agency it finds under `~` (a `.agency` directory to depth 3: `master`,
   `agency/communications` and `agency/humanities` on 28 Nov). A file there
   with a "Done means" section becomes a Ticket at once, by rule, and starts
   the default recipe; a file without one is logged as not offered.

## Start, stop, logs

```
systemctl --user start factory-floor        # by hand; nothing else starts it
systemctl --user status factory-floor
journalctl --user -u factory-floor -f
agency status
systemctl --user stop factory-floor         # SIGTERM; workers keep running in hc
```

A switch does not restart a running floor (`keep-old`). To pick up a new
package or profile, restart it yourself: `systemctl --user restart factory-floor`.
If the start limit tripped (10 starts in 10 minutes), run
`systemctl --user reset-failed factory-floor` first.

## The flips (Tom's)

```nix
services.factory-floor.autostart = true;      # WantedBy=default.target: up at boot (and started by the switch)
services.factory-floor.heartbeatWake = true;  # floorUnit = "factory-floor.service"
services.factory-floor.overlay = [ ];         # drop the overlay: the scheduled Source reads the live inbox
```

To read only some agencies' Intents, add a row to the overlay, beside the
scheduled one: `{ id = "source-intent"; config = { agencies = [ "master" ]; }; }`
(the row has no other config, so replacing it loses nothing).

With the overlay dropped, the floor turns each waiting record into a Ticket and
launches the default recipe for it. When `heartbeatWake` is on, `home/scheduled.nix`
passes `SCHEDULED_FLOOR_UNIT=factory-floor.service` to the heartbeat, and a tick
with records waiting runs `systemctl --user start --no-block` on the floor
(docs/scheduled.md). `tests/factory-floor` evaluates both flips.

## Moving the pin

The code the floor runs is chosen by the `agency` input's rev in `flake.nix`.
Move it by editing that rev, then `nix flake update agency`, then build. (An
`--override-input` changes only the lock and leaves `flake.nix` naming the old
rev.) No
`nixpkgs.follows`: the package's pnpm-deps hash is fixed against the repository's
own nixpkgs, and the repository's `nix/README.md` says how to refresh it.

## Not done here

- No new timer, no `OnCalendar`, no unit on the seat or on strix.
