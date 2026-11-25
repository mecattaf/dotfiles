# Scheduled in a NixOS VM (AGENTS.md D52; docs/scheduled.md).
#
# One VM `nas`: the fleet-role module with the brain role, a lingering
# uid-1000 user tom, and the real home/scheduled.nix under Home Manager, so
# the heartbeat timer and service under test are the NAS's own text. The
# node adds one line to that text, SCHEDULED_FLOOR_UNIT=floor-stub.service;
# the NAS itself names no floor unit tonight (the null-floor subtest runs
# that mode). A specialisation `next` changes only the service text.
#
# The floor is a stub user unit, floor-stub.service, declared and not
# wanted by default.target (as home/factory-floor.nix declares the real
# floor): while it runs, a loop drains the inbox every second with the stub
# Source, which moves each record to .done/ and fails the unit on a torn or
# partial one. The heartbeat wakes it with `systemctl --user start
# --no-block` (pkgs/scheduled, floor.mjs).
#
# Subtests: shape (condition skip before ~/.agency), C3.1 first tick, S8
# clock back, S1 hand-off (3 h gap: one record, missed 2; it starts the
# stopped floor unit, which drains it; a repeat makes none), S4 power cut
# (one record at boot, which starts the floor unit again; none from the
# OnStartupSec tick after it), S3 switch (the timer is not restarted, the
# next tick runs the new text), S6 surfacing (the floor unit named is not
# found and a record waits: the tick fails the unit, nothing is started),
# null-floor (no SCHEDULED_FLOOR_UNIT, the NAS's mode tonight: a due tick
# links its record, exits 0, logs no floor line and the record waits),
# withdraw (an item disabled while its record waits and the floor is
# stopped), the run-now storm (1000 runs, one without a bus; the drain
# loses none) and run waking a stopped floor unit. Not covered here: the
# wake table row by row (the package tests), S5 (a cut inside a profile
# set) and the failure-marker hashes of S6 (modules/failure-surfacing.nix).
{ inputs, configurations }:
let
  pkgs = configurations.nas.pkgs;
  inherit (pkgs) lib;
  # The stub Source (P9.2): every <inbox>/*.json must parse as one
  # complete occurrence record v1 of kind schedule or manual, then it
  # moves to .done/. A torn or partial record fails the check.
  stubFloor = pkgs.writers.writePython3 "stub-floor" { } ''
    import json
    import os
    import sys

    REQUIRED = {"v", "kind", "namespace", "item", "cwd", "file", "due",
                "missed", "revision", "text", "by", "at"}
    inbox = sys.argv[1]
    done = os.path.join(inbox, ".done")
    os.makedirs(done, exist_ok=True)
    kinds = {}
    for name in sorted(os.listdir(inbox)):
        if name.startswith(".") or not name.endswith(".json"):
            continue
        path = os.path.join(inbox, name)
        with open(path) as handle:
            record = json.load(handle)
        assert record["v"] == 1 and REQUIRED <= set(record), name
        kind = record["kind"]
        assert kind in ("schedule", "manual"), name
        assert (kind == "manual") == ("run" in record), name
        kinds[kind] = kinds.get(kind, 0) + 1
        os.rename(path, os.path.join(done, name))
    print(json.dumps(kinds))
  '';
  inbox = "/home/tom/.agency/state/master/inbox/scheduled";
  floorUnit = "floor-stub.service";
  # The floor stand-in: the stub Source over the inbox once a second, while
  # the unit runs. It waits for the heartbeat to make the inbox (0700), and
  # a bad record ends the loop, so the unit fails and the test sees it.
  floorLoop = pkgs.writeShellScript "floor-stub" ''
    set -eu
    while :; do
      if [ -d ${inbox} ]; then
        out=$(${stubFloor} ${inbox})
        [ "$out" = "{}" ] || echo "drained $out"
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in
pkgs.testers.runNixOSTest {
  name = "scheduled-vm";
  globalTimeout = 2400;
  nodes.nas = {
    imports = [
      # home/scheduled.nix is gated on the brain role (osConfig.myFleet.has).
      ../../modules/fleet-role.nix
      inputs.home-manager-nas.nixosModules.home-manager
    ];
    myFleet.roles = [ "brain" ];
    users.users.tom = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.tom = {
        imports = [ ../../home/scheduled.nix ];
        # The one line the NAS does not have tonight: the floor unit to wake.
        systemd.user.services.scheduled-heartbeat.Service.Environment = [
          "SCHEDULED_FLOOR_UNIT=${floorUnit}"
        ];
        # Declared, never wanted: only the heartbeat (or the test) starts it.
        systemd.user.services.floor-stub = {
          Unit.Description = "Stub floor: drains the scheduled inbox every second";
          Service = {
            Type = "exec";
            ExecStart = "${floorLoop}";
            UMask = "0077";
          };
        };
        home.stateVersion = "26.05";
      };
    };
    # The test sets the clock by hand.
    services.timesyncd.enable = false;
    # A persistent machine id, as on the NAS (a plain file there): the tick refuses
    # a heartbeat.json from another machine (C3.6), so a fresh id per boot would
    # stop every tick after the power cut.
    environment.etc."machine-id" = { text = "5c4f1e0b2a7d4e9c8f3b6a1d2e7c9b04\n"; mode = "0444"; };
    environment.systemPackages = [ pkgs.jq ];
    virtualisation.memorySize = 3072;
    virtualisation.cores = 4;
    specialisation.next.configuration = {
      home-manager.users.tom.systemd.user.services.scheduled-heartbeat.Service.Environment = lib.mkForce [
        "PATH=/run/current-system/sw/bin"
        "SCHEDULED_INBOX=${inbox}"
        "SCHEDULED_FLOOR_UNIT=${floorUnit}"
        "SCHEDULED_VM_NEXT=1"
      ];
    };
  };
  testScript = ''
    import datetime as dt
    import json
    import os
    import re
    import shlex

    INBOX = "${inbox}"
    DONE = f"{INBOX}/.done"
    STATE = "/home/tom/.local/state/scheduled"
    STUB_FLOOR = "${stubFloor}"
    FLOOR = "${floorUnit}"
    # The installed command carries the inbox as a default (home/scheduled.nix):
    # a login shell runs it with no environment. It names no floor unit (the
    # NAS's mode), so CLI names the stub's; the storm sets it empty.
    CLI = f"env -u SCHEDULED_INBOX SCHEDULED_FLOOR_UNIT={FLOOR}"
    CLI_NO_FLOOR = "env -u SCHEDULED_INBOX SCHEDULED_FLOOR_UNIT="
    # A runtime drop-in for the heartbeat service: S6 and null-floor change
    # its floor unit for a while; a reboot would drop it.
    DROPIN = "$XDG_RUNTIME_DIR/systemd/user/scheduled-heartbeat.service.d"
    WAIT = 300
    # S4 boots the guest with its clock this far past an hour mark, so the
    # boot tick and the OnStartupSec tick two minutes later share an hour.
    S4_PAST_HOUR = 300


    def tom(command: str, bus: bool = True) -> str:
        """A root shell command that runs `command` as tom."""
        env = ('rt="$(loginctl show-user tom --property=RuntimePath --value)"; '
               'export XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"; ') if bus else ""
        return "su -l tom -c " + shlex.quote("set -eu; " + env + command)


    def run(command: str, bus: bool = True, timeout: int = WAIT) -> str:
        return nas.succeed(tom(command, bus), timeout=timeout)


    def show(unit: str, prop: str) -> str:
        return run(f"systemctl --user show --property={prop} --value {unit}").strip()


    def tick() -> str:
        """Starts the heartbeat service once, as the timer would; its result."""
        run("systemctl --user start scheduled-heartbeat.service || true")
        return show("scheduled-heartbeat.service", "Result")


    def names(directory: str) -> list[str]:
        out = run(f"ls -1 {directory} 2>/dev/null || true")
        return [n for n in out.split() if n.endswith(".json") and not n.startswith(".")]


    def records() -> list[str]:
        """The heartbeat's records waiting in the inbox (manual runs excluded)."""
        return [n for n in names(INBOX) if "@run~" not in n]


    def manual() -> list[str]:
        return [n for n in names(INBOX) if "@run~" in n]


    def handed() -> set[str]:
        """Every heartbeat record handed off so far: waiting, or drained to .done/ by the stub floor."""
        return {n for n in names(INBOX) + names(DONE) if "@run~" not in n}


    def floor_state() -> str:
        """The stub floor unit's ActiveState: inactive when stopped by intent."""
        return show(FLOOR, "ActiveState")


    def stop_floor() -> None:
        """The floor stopped by intent: an inactive unit, never failed."""
        run(f"systemctl --user stop {FLOOR}")
        assert floor_state() == "inactive", floor_state()
        assert show(FLOOR, "Result") == "success", show(FLOOR, "Result")


    def shift(seconds: int) -> None:
        nas.succeed(f"date -s @$(( $(date +%s) + ({seconds}) ))")


    def last_tick() -> str:
        return json.loads(run(f"cat {STATE}/heartbeat.json"))["lastTick"]


    def journal() -> str:
        return nas.succeed("journalctl --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 || true")


    def floor_lines() -> int:
        """How many wake-table lines the heartbeat has logged in all."""
        return len(re.findall(r"^(<\d>)?floor ", journal(), re.M))


    def passes() -> int:
        """How many tick summaries (`pass reason=…`, a tick's last line) the heartbeat has logged."""
        return journal().count("pass reason=")


    def dropin(text: str | None) -> None:
        """Replaces the heartbeat's runtime drop-in with one [Service] line (None: removes it)."""
        if text is None:
            run(f"rm -rf {DROPIN}")
        else:
            run(f"mkdir -p {DROPIN} && printf '[Service]\\n%s\\n' {shlex.quote(text)} > {DROPIN}/50-vm.conf")
        run("systemctl --user daemon-reload")


    def quiet() -> None:
        """Waits until no tick runs or is queued."""
        nas.wait_until_succeeds(tom(
            'test -z "$(systemctl --user list-jobs --no-legend)"'
            ' && test "$(systemctl --user show -p ActiveState --value scheduled-heartbeat.service)" != activating'
        ), timeout=WAIT)


    def hours(iso: str) -> int:
        return int(dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()) // 3600


    def diagnose() -> None:
        """What a failed wait needs: clock, state, ids, timers, the floor unit, the tick journal."""
        print(nas.execute(tom(f"date -u; cat {STATE}/heartbeat.json; cat /etc/machine-id; systemctl --user list-timers --all --no-legend;"
                              " systemctl --user show -p Result,ConditionResult,ActiveState scheduled-heartbeat.service;"
                              f" systemctl --user show -p Result,ActiveState,SubState {FLOOR}; ls -la {INBOX}") + " 2>&1")[1])
        print(nas.execute("journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=scheduled-heartbeat.service | tail -30")[1])
        print(nas.execute(f"journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT={FLOOR} | tail -20")[1])


    def wait_tick(previous: str) -> None:
        try:
            nas.wait_until_succeeds(tom(f"test \"$(jq -r .lastTick {STATE}/heartbeat.json)\" != {shlex.quote(previous)}"), timeout=WAIT)
        except Exception:
            diagnose()
            raise


    def drained() -> None:
        """Waits until the woken stub floor runs and nothing waits in the inbox."""
        try:
            nas.wait_until_succeeds(tom(f"systemctl --user is-active --quiet {FLOOR} && ! ls -1 {INBOX} | grep -q '[.]json$'"), timeout=WAIT)
        except Exception:
            diagnose()
            raise


    def boot() -> None:
        nas.wait_for_unit("multi-user.target")
        nas.wait_for_unit("default.target", "tom")


    start_all()
    boot()
    # The test drives every tick until S4; the boot tick of OnStartupSec
    # must not fire under it.
    run("systemctl --user stop scheduled-heartbeat.timer")

    with subtest("shape: the NAS's own units, skipped by condition before ~/.agency exists"):
        assert show("scheduled-heartbeat.timer", "UnitFileState") == "enabled", show("scheduled-heartbeat.timer", "UnitFileState")
        assert show("scheduled-heartbeat.service", "Type") == "oneshot"
        environment = show("scheduled-heartbeat.service", "Environment")
        assert f"SCHEDULED_INBOX={INBOX}" in environment and f"SCHEDULED_FLOOR_UNIT={FLOOR}" in environment, environment
        # The unit text, not systemctl's "# /path" header (a store link under Home Manager).
        text = [line for line in run("systemctl --user cat scheduled-heartbeat.timer").splitlines() if not line.startswith("# /")]
        assert not any("/nix/store/" in line for line in text), text
        run("systemctl --user start scheduled-heartbeat.service")
        assert show("scheduled-heartbeat.service", "ConditionResult") == "no"
        assert show("scheduled-heartbeat.service", "Result") == "success"
        # Declared and not wanted: nothing started the floor at boot.
        assert show(FLOOR, "LoadState") == "loaded" and floor_state() == "inactive", floor_state()
        run("scheduled --version")

    with subtest("setup: the floor is stopped by intent, one enabled item, one disabled"):
        stop_floor()
        run("install -d -m 0700 ~/.agency")
        run("scheduled new master:hb --cron '0 * * * *' --tz UTC --prompt 'Say ok.'")
        run("scheduled set master:hb enabled true")
        run("scheduled new master:off --cron '0 * * * *' --tz UTC --prompt 'Say ok.'")
        run("scheduled validate --all")
        # Six hours back: room for S8, S1 and S4 below.
        shift(-6 * 3600)

    with subtest("C3.1: the first tick hands off nothing; the floor stays stopped"):
        assert tick() == "success"
        assert handed() == set(), handed()
        assert floor_state() == "inactive"
        first = last_tick()

    with subtest("S8: a clock one hour back hands off nothing and keeps lastTick"):
        shift(-3600)
        assert tick() == "success"
        assert handed() == set()
        assert last_tick() == first
        assert "clock went back" in journal()

    with subtest("S1: a three-hour gap hands off one record with missed 2 and starts the floor unit; a repeat makes none"):
        shift(4 * 3600)
        assert tick() == "success"
        # Stopped by intent, and a record waits: the tick queues a start of the floor unit.
        assert re.search(rf"floor action=start unit={re.escape(FLOOR)} state=stopped waiting=1 result=queued", journal()), journal()
        # The floor runs and its Source drains the record to .done/.
        drained()
        made = sorted(handed())
        assert len(made) == 1 and records() == [], (made, records())
        record = json.loads(run(f"cat {DONE}/{made[0]}"))
        # Three hour marks lie in the gap (four if the test itself crossed one).
        marks = hours(last_tick()) - hours(first)
        assert marks in (3, 4) and record["namespace"] == "master" and record["item"] == "hb", (record, marks)
        assert record["missed"] == marks - 1 and record["cwd"] == "/home/tom" and record["text"] == "Say ok.", record
        # The heartbeat made the inbox 0700 and the record 0600 (a rename keeps the mode).
        assert run(f"stat -c %a {INBOX} {DONE}/{made[0]}").split() == ["700", "600"]
        assert run(f"stat -c %a {STATE}").strip() == "700"
        assert tick() == "success"
        assert sorted(handed()) == made and records() == []
        # The disabled item hands off nothing.
        assert not any("~off@" in n for n in made)

    with subtest("S4: power cut; one record at boot, none from the OnStartupSec tick after it"):
        run("systemctl --user start scheduled-heartbeat.timer")
        wait_tick(last_tick())
        # The floor runs since S1: let it drain what that tick handed off. Its renames
        # to .done/ are not crash-safe (no fsync), so a drained file may be back in the
        # inbox after the cut; the real Source answers duplicate for it. Count only the
        # names the reboot hands off, wherever they lie.
        drained()
        pending = handed()
        before = last_tick()
        nas.crash()
        # The guest clock would come back at host time, about three hours on, and the
        # two ticks below would straddle an hour mark whenever the cut fell within
        # about 150 s before one (the second tick then rightly hands off the new hour).
        # Pin it instead, from the guest's own last tick: S4_PAST_HOUR past the hour,
        # three hours on. The VM's run script reads QEMU_OPTS.
        pin = (hours(before) + 3) * 3600 + S4_PAST_HOUR
        saved = os.environ.get("QEMU_OPTS")
        os.environ["QEMU_OPTS"] = f"-rtc base={dt.datetime.fromtimestamp(pin, dt.timezone.utc):%Y-%m-%dT%H:%M:%S}"
        try:
            nas.start(allow_reboot=True)
        finally:
            if saved is None:
                del os.environ["QEMU_OPTS"]
            else:
                os.environ["QEMU_OPTS"] = saved
        boot()
        wait_tick(before)
        print(f"S4: pin {pin}, boot tick {last_tick()}, guest {nas.succeed('date -u +%FT%TZ').strip()}")
        # The pin held: the boot tick ran in the pinned hour.
        assert hours(last_tick()) == pin // 3600, (last_tick(), pin)
        after_boot = handed()
        fresh = after_boot - pending
        assert len(fresh) == 1, (after_boot, pending)
        # The floor unit was running at the cut and is not wanted at boot: after the
        # reboot it is inactive, a record waits, and the boot tick starts it.
        this_boot = nas.succeed("journalctl -b --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 || true")
        assert re.search(rf"floor action=start unit={re.escape(FLOOR)} state=stopped waiting=\d+ result=queued", this_boot), this_boot
        drained()
        # The OnStartupSec tick, two minutes after the manager started.
        nas.sleep(150)
        quiet()
        assert handed() == after_boot, (handed(), after_boot)
        assert show("scheduled-heartbeat.service", "Result") == "success"

    with subtest("S3: a switch keeps the timer and the next tick runs the new text"):
        trigger = show("scheduled-heartbeat.timer", "LastTriggerUSec")
        entered = show("scheduled-heartbeat.timer", "ActiveEnterTimestampMonotonic")
        toplevel = nas.succeed("readlink -f /run/current-system").strip()
        nas.succeed(f"{toplevel}/specialisation/next/bin/switch-to-configuration test 2>&1")
        nas.wait_until_succeeds(tom("systemctl --user cat scheduled-heartbeat.service | grep -q SCHEDULED_VM_NEXT"), timeout=WAIT)
        assert show("scheduled-heartbeat.timer", "LastTriggerUSec") == trigger
        assert show("scheduled-heartbeat.timer", "ActiveEnterTimestampMonotonic") == entered
        assert tick() == "success"
        assert "SCHEDULED_VM_NEXT=1" in show("scheduled-heartbeat.service", "Environment")

    with subtest("S6: the floor unit named is not found and a record waits; the tick fails the unit, nothing is started"):
        # From here the test drives every tick again: a clock shift would fire the timer.
        run("systemctl --user stop scheduled-heartbeat.timer")
        quiet()
        stop_floor()
        dropin("Environment=SCHEDULED_FLOOR_UNIT=missing.service")
        assert "SCHEDULED_FLOOR_UNIT=missing.service" in show("scheduled-heartbeat.service", "Environment")
        assert show("missing.service", "LoadState") == "not-found"
        waiting = records()
        # The next hour mark: one record for master:hb.
        shift(3600)
        assert tick() == "exit-code"
        assert re.search(r"floor (unit=missing\.service )?state=not-found", journal()), journal()
        assert len(records()) == len(waiting) + 1, (records(), waiting)
        assert floor_state() == "inactive" and show("missing.service", "ActiveState") == "inactive"

    with subtest("null-floor: no SCHEDULED_FLOOR_UNIT (the NAS tonight); a due tick links its record, exits 0, logs no floor line"):
        # The NAS's unit has no floor variable at all; the drop-in takes the node's away.
        dropin("UnsetEnvironment=SCHEDULED_FLOOR_UNIT")
        assert "SCHEDULED_FLOOR_UNIT" in show("scheduled-heartbeat.service", "UnsetEnvironment")
        waiting = records()
        logged, passed = floor_lines(), passes()
        shift(3600)
        assert tick() == "success"
        new = [n for n in records() if n not in waiting]
        assert len(new) == 1 and "~hb@" in new[0], (records(), waiting)
        # The tick's last line (its pass summary) is in the journal, and no floor
        # line before it: the tick read no unit and started none.
        nas.wait_until_succeeds(f"test \"$(journalctl --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 | grep -c 'pass reason=')\" -gt {passed}", timeout=WAIT)
        assert floor_lines() == logged, journal()
        # Nothing drains it: the record stays in the inbox for a floor to come.
        nas.sleep(3)
        assert new[0] in records() and floor_state() == "inactive"
        dropin(None)

    with subtest("withdraw: an item disabled while its record waits and the floor is stopped loses that record"):
        assert floor_state() == "inactive"
        waiting = records()
        assert waiting, "S6 and null-floor left records waiting"
        run("scheduled set master:hb enabled false")
        # Older than the 2 s young-file rule, so this tick reads the edit.
        nas.sleep(3)
        assert tick() == "success"
        assert records() == [], records()
        assert "reason=disabled" in journal() and "withdrawn occurrence=master~hb@" in journal()
        # Nothing waits after the withdrawal: the floor stays stopped.
        assert floor_state() == "inactive"

    with subtest("P9.2: a run-now storm of 1000, one requester without a bus; the drain loses none"):
        # One Node process per request: minutes, not seconds. No floor unit, so the
        # storm tests only the hand-off; the next subtest wakes the floor. The timer
        # is held off: a tick that sees these records waiting starts the floor unit
        # (the wake rule), and the floor's drain would race the hand drain below.
        run("systemctl --user stop scheduled-heartbeat.timer")
        quiet()
        run(f"seq 999 | xargs -P 8 -I{{}} {CLI_NO_FLOOR} scheduled run master:hb >/dev/null", timeout=1500)
        run(f"{CLI_NO_FLOOR} scheduled run master:hb >/dev/null", bus=False)
        # A disabled item runs by hand: enabled false cancels only scheduled occurrences.
        run(f"{CLI_NO_FLOOR} scheduled run master:off >/dev/null")
        assert len(manual()) == 1001, len(manual())
        assert run(f"ls -A {INBOX}/.tmp | wc -l").strip() == "0"
        kinds = json.loads(run(f"{STUB_FLOOR} {INBOX}"))
        assert kinds == {"manual": 1001}, kinds
        assert manual() == [] and records() == []
        assert floor_state() == "inactive"

    with subtest("run: a manual record wakes a stopped floor unit once; it drains; history lists what the drain received"):
        out = json.loads(run(f"{CLI} scheduled run master:hb --json"))
        assert out["floor"].startswith(f"floor action=start unit={FLOOR} state=stopped") and out["floor"].endswith("result=queued"), out
        drained()
        assert manual() == [] and names(DONE).count(out["occurrence"] + ".json") == 1, out
        rows = json.loads(run(f"{CLI} scheduled history master:off --json"))["rows"]
        assert [r["state"] for r in rows] == ["done"] and rows[0]["kind"] == "manual", rows
        # The stub floor met no torn record all along: it still runs.
        assert floor_state() == "active", floor_state()
        run("systemctl --user start scheduled-heartbeat.timer")
  '';
}
