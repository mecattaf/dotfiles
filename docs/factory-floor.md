# factory-floor.service

The factory floor (`agency`, repository `agency-agency/factory-floor`) is a
Cordis orchestrator on herdr-core. It replaces the retired dshd instance `floor`
(2026-11-26). `home/factory-floor.nix` declares its user unit on the brain host
(the NAS) through the floor flake's Home Manager module (flake input
`factory-floor`, pinned by rev; `nix/module.nix` in that repository). The unit
is modelled on `communications.service`.

Two modes, one option:

- **Store mode** (this repository's setting): `package` is the floor flake's
  package. The unit runs its `bin/agency-service` from the store, and `agency`
  is on PATH (`/etc/profiles/per-user/tom/bin/agency`). A new floor is a rev
  bump of the input plus `nix flake lock`.
- **Checkout mode**: `package = null`. The unit runs the entry of the local
  checkout `~/mecattaf/factory-floor`, built by hand. The launcher store path
  is the same in both modes; only `FACTORY_FLOOR_ENTRY` and
  `ConditionPathExists` change.

Checks: `checks.factory-floor` (`tests/factory-floor`), which asserts store mode.

## What is declared

| Item | Value on the NAS |
|---|---|
| Unit | `factory-floor.service` (user), `Type=exec`, `Restart=on-failure`, `RestartSec=15`, `UMask=0077`, `KillSignal=SIGTERM`, `TimeoutStopSec=60`, `StartLimitIntervalSec=600`, `StartLimitBurst=10`, `RestartPreventExitStatus=78` |
| Ordering | `After=network-online.target hc-core.service`, `Wants=hc-core.service` |
| Condition | `ConditionPathExists=<entry>`: with no entry (checkout mode, no checkout), a start is skipped and no unit fails |
| Switch | `X-SwitchMethod=keep-old`: a switch never restarts a running floor |
| Install | none: wanted by no target, so it never starts at boot or at switch (`autostart = false`) |
| ExecStart | a store launcher, `factory-floor-service`, that execs the entry with no arguments |
| Heartbeat wake | off (`heartbeatWake = false`, `floorUnit = null`) |

The options are `services.factory-floor.{enable, package, installPackage, hcPackage,
checkout, entry, stateDir, workDir, configDir, host, port, autostart,
heartbeatWake, overlay, require, bundles, unsetEnvironment, documentation}`,
plus the read-only `floorUnit` and `launcher` (the floor repository's
`nix/README.md`). This repository sets `enable` to the brain role and
`documentation` to this page. No other host has the unit.

## The contract with the floor repository

1. **Entry.** The unit runs `<package>/bin/agency-service` in store mode, or
   `~/mecattaf/factory-floor/bin/agency-service` in checkout mode (option
   `entry`), with no arguments. The floor repository provides this
   file. It is a foreground process that exits non-zero when a plugin fails to
   start, ends within 60 s of SIGTERM, and never builds. It is expected to run
   `agency serve --profile floor` with the values below.
2. **Built checkout (checkout mode only).** The unit never builds, fetches or
   installs. Build first:
   `cd ~/mecattaf/factory-floor && pnpm install && pnpm build`. If the entry
   is missing or not executable, the launcher prints "build the checkout first
   (pnpm install && pnpm build)" and exits 78. The unit then fails without
   restarting.
3. **PATH.** `node` (nixpkgs `nodejs_24`) and the fleet's `herdr-core` come
   first, then `/run/current-system/sw/bin`. No other tool is promised.
4. **Environment.** The floor's defaults must equal these values. Writes stay
   inside the three directories.

   | Variable | Value |
   |---|---|
   | `FACTORY_FLOOR_CHECKOUT` | `/home/tom/mecattaf/factory-floor` |
   | `FACTORY_FLOOR_ENTRY` | `<package>/bin/agency-service` (store mode), or `/home/tom/mecattaf/factory-floor/bin/agency-service` (checkout mode) |
   | `FACTORY_FLOOR_STATE_DIR` | `/home/tom/.agency/state/master/factory-floor`: a fresh directory, never the retired `orchestrator.sqlite` beside it |
   | `FACTORY_FLOOR_WORK_DIR` | `/home/tom/.local/state/factory-floor` |
   | `FACTORY_FLOOR_CONFIG_DIR` | `/home/tom/.config/agency/factory-floor`: holds `floor.jsonc`, host-local, never in this repository |
   | `FACTORY_FLOOR_HOST` | `127.0.0.1`: loopback only (a wildcard fails evaluation) |
   | `FACTORY_FLOOR_PORT` | `3082`: `scheduled-panel-tunnel` already forwards it to the seat |
   | `HC_BIN` | the store path of the fleet's `herdr-core` |

   The unit unsets the same per-launch names as `hc-core.service`
   (`CLAUDECODE`, `CLAUDE_CODE_*`, `DSH_*`, `HC_SESSION`, `HC_SOCKET`, ...).
   A floor that inherits a Claude Code session's variables would hand them to
   its workers.
5. **Health.** Either `~/mecattaf/factory-floor/bin/agency status --json`
   (exit 0 when the service answers), or `GET http://127.0.0.1:3082/api/health`
   or `/healthz` returning 200.
6. **hc.** The floor uses the declared core on the default socket
   (`$XDG_RUNTIME_DIR/herdr-core/default.sock`). It never starts a core: a
   missing socket means waiting for `hc-core.service`. Workers live in hc's own
   holder units, not in this unit's cgroup, so stopping the floor ends no agent.
   The floor labels its workers with its own keys. It never types into a
   terminal labelled `owner=tom` and never kills one. It does not write under
   `~/.config/herdr-core/`.
7. **Scheduled inbox.** The heartbeat links records into
   `~/.agency/state/master/inbox/scheduled`. That inbox holds the host's real
   items (`journal-day`, `fleet-update`, `chats`). By default the floor's
   scheduled Source reads its own `<stateDir>/inbox/scheduled`. It reads the
   live inbox only when `floor.jsonc` names it explicitly. The floor adds no
   clock of its own.

## Start, stop, logs

```
systemctl --user start factory-floor        # by hand; nothing else starts it
systemctl --user status factory-floor
journalctl --user -u factory-floor -f
~/mecattaf/factory-floor/bin/agency status --json
systemctl --user stop factory-floor         # SIGTERM; workers keep running in hc
```

A switch does not restart a running floor (`keep-old`). To pick up a new
launcher or a rebuilt checkout, restart it yourself:
`systemctl --user restart factory-floor`. If the start limit tripped
(10 starts in 10 minutes), run `systemctl --user reset-failed factory-floor`
first.

## The two flips (Tom's)

Both live in `home/factory-floor.nix` or in a host block:

```nix
services.factory-floor.autostart = true;      # WantedBy=default.target: up at boot (and started by the switch)
services.factory-floor.heartbeatWake = true;  # floorUnit = "factory-floor.service"
```

When `heartbeatWake` is on, `home/scheduled.nix` passes
`SCHEDULED_FLOOR_UNIT=factory-floor.service` to the heartbeat. A tick with
records waiting then runs `systemctl --user start --no-block` on the floor
(docs/scheduled.md). Turn it on only when the floor's scheduled Source reads the
live inbox and you want it to act on those items unattended. `tests/factory-floor`
evaluates both flips, so neither is first evaluated on the day it is made.

## Running the floor on a host that was not switched

If the NAS still runs a generation without this unit, run the same program as a
transient unit. It gets the user manager's environment, not the calling shell's.
The fleet does not put node on the NAS PATH, so name a node 24:

```
node24=$(nix build --no-link --print-out-paths nixpkgs#nodejs_24)/bin
systemd-run --user --unit factory-floor-dev --collect -p Restart=no \
  -p UMask=0077 -p KillSignal=SIGTERM -p TimeoutStopSec=60 \
  -p UnsetEnvironment="CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_EXECPATH CLAUDE_PID CLAUDE_EFFORT CLAUDE_ENVELOPE CODEX_THREAD_ID DSH_SESSION_ID DSH_SHELL DSH_PROFILE_DIR DSH_WEB_URL HC_SESSION HC_SOCKET HC_TERMINAL_ID HC_TERMINAL_SOCKET CLOUDFLARE_API_TOKEN" \
  -E PATH="$node24:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin" \
  -E FACTORY_FLOOR_CHECKOUT="$HOME/mecattaf/factory-floor" \
  -E FACTORY_FLOOR_ENTRY="$HOME/mecattaf/factory-floor/bin/agency-service" \
  -E FACTORY_FLOOR_STATE_DIR="$HOME/.agency/state/master/factory-floor" \
  -E FACTORY_FLOOR_WORK_DIR="$HOME/.local/state/factory-floor" \
  -E FACTORY_FLOOR_CONFIG_DIR="$HOME/.config/agency/factory-floor" \
  -E FACTORY_FLOOR_HOST=127.0.0.1 -E FACTORY_FLOOR_PORT=3082 \
  -E HC_BIN=/etc/profiles/per-user/$USER/bin/herdr-core \
  "$HOME/mecattaf/factory-floor/bin/agency-service"
```

Stop it with `systemctl --user stop factory-floor-dev`. A reboot removes it.
Check first that `ss -ltn | grep ':3082'` is empty and that the declared core
answers (`herdr-core server status`). Never start a core from inside a Claude
Code session.

## Not done here

- The host-local `floor.jsonc` is not managed here. Its recipes' `AGENCY_BIN`
  and the `fake` recipe's paths may still name the checkout; for pure store
  mode, point `AGENCY_BIN` at `/etc/profiles/per-user/tom/bin/agency`.
- No new timer, no `OnCalendar`, no unit on the seat or on strix.
