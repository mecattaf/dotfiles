# factory-floor.service

The factory floor (`agency`, repository `~/mecattaf/factory-floor`) is a Cordis
orchestrator on herdr-core. It replaces the retired dshd instance `floor`
(2026-11-26). `home/factory-floor.nix` declares its user unit on the brain host
(the NAS). The unit is modelled on `communications.service` and runs the entry of
a local checkout. Checks: `checks.factory-floor` (`tests/factory-floor`).

## What is declared

| Item | Value on the NAS |
|---|---|
| Unit | `factory-floor.service` (user), `Type=exec`, `Restart=on-failure`, `RestartSec=15`, `UMask=0077`, `KillSignal=SIGTERM`, `TimeoutStopSec=60`, `StartLimitIntervalSec=600`, `StartLimitBurst=10`, `RestartPreventExitStatus=78` |
| Ordering | `After=network-online.target hc-core.service`, `Wants=hc-core.service` |
| Condition | `ConditionPathExists=<entry>`: with no checkout, a start is skipped and no unit fails |
| Switch | `X-SwitchMethod=keep-old`: a switch never restarts a running floor |
| Install | `WantedBy=default.target` (`autostart = true` in `hosts/nas/default.nix`): up at boot, and started by a switch that adds the want, when the entry exists |
| ExecStart | a store launcher, `factory-floor-service`, that execs the entry with no arguments |
| Heartbeat wake | on (`heartbeatWake = true` in `hosts/nas/default.nix`, `floorUnit = "factory-floor.service"`): a tick with records waiting starts the unit |

The options are `services.factory-floor.{enable, package, checkout, entry, stateDir,
workDir, configDir, host, port, autostart, heartbeatWake}`, plus the read-only
`floorUnit`. `enable` defaults to the brain role. No other host has the unit.
`autostart` and `heartbeatWake` default to off; the NAS turns both on in
`hosts/nas/default.nix` ([The two flips](#the-two-flips-toms)).

## The contract with the floor repository

1. **Entry.** The unit runs `~/mecattaf/factory-floor/bin/agency-service`
   (option `entry`) with no arguments. The floor repository provides this
   file. It is a foreground process that exits non-zero when a plugin fails to
   start, ends within 60 s of SIGTERM, and never builds. It is expected to run
   `agency serve --profile floor` with the values below.
2. **Built checkout.** The unit never builds, fetches or installs. Build first:
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
   | `FACTORY_FLOOR_ENTRY` | `/home/tom/mecattaf/factory-floor/bin/agency-service` |
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
systemctl --user start factory-floor        # by hand; boot and the heartbeat also start it
systemctl --user status factory-floor
journalctl --user -u factory-floor -f
~/mecattaf/factory-floor/bin/agency status --json
systemctl --user stop factory-floor         # SIGTERM; workers keep running in hc
```

With the heartbeat wake on, a stop holds only until the next tick that finds
a record waiting. To keep the floor down, stop the clock first
(`systemctl --user stop scheduled-heartbeat.timer`, until the next boot or a
switch that changes the timer), or disable the items
(`scheduled set ID enabled false`), or delete the flips block and switch.
`systemctl --user mask` is no help here: the unit file is a Home Manager link
in `~/.config/systemd/user`, which a mask will not replace.

A switch does not restart a running floor (`keep-old`). To pick up a new
launcher or a rebuilt checkout, restart it yourself:
`systemctl --user restart factory-floor`. If the start limit tripped
(10 starts in 10 minutes), run `systemctl --user reset-failed factory-floor`
first.

## The two flips (Tom's)

Both default to off in `home/factory-floor.nix`. The NAS turns both on in a
host block, `hosts/nas/default.nix`:

```nix
home-manager.users.tom.services.factory-floor = {
  autostart = true;      # WantedBy=default.target: up at boot (and started by the switch)
  heartbeatWake = true;  # floorUnit = "factory-floor.service"
};
```

Delete the block to turn both off again.

When `heartbeatWake` is on, `home/scheduled.nix` passes
`SCHEDULED_FLOOR_UNIT=factory-floor.service` to the heartbeat. A tick with
records waiting then runs `systemctl --user start --no-block` on the floor
(docs/scheduled.md). Turn it on only when the floor's scheduled Source reads the
live inbox and you want it to act on those items unattended. Once it is on, a
hand `systemctl --user stop` holds only until the next tick that finds a
record waiting ([Start, stop, logs](#start-stop-logs) says how to keep it
down). `tests/factory-floor` evaluates the way back (both off), so a revert
is never a first evaluation.

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

- The floor is not a flake input yet. Once its repository has a flake, set
  `package`: `entry` then defaults to the package's `bin/agency-service`, and
  no checkout needs to be built.
- No new timer, no `OnCalendar`, no unit on the seat or on strix.
