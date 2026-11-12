# Scheduled in a NixOS VM (AGENTS.md D52; scheduled-jsonc §8).
#
# One VM `nas`: the dshd module from the dshd input with the upstream stub
# dsh (checks/stub-dsh.nix, DSH_STUB_MODE), a lingering uid-1000 user tom,
# and the real home/scheduled.nix under Home Manager, so the heartbeat
# timer and service under test are the NAS's own text. A specialisation
# `next` changes only the service text. The floor is a stub dsh web
# instance named `floor`; a stub drain stands in for the fork's scheduled
# Source and moves each inbox record to .done/.
#
# Subtests: shape (condition skip before ~/.agency), C3.1 first tick, S8
# clock back, S1 hand-off (3 h gap: one record, missed 2; it starts the
# stopped floor; a repeat makes none), S4 power cut (one record at boot,
# none from the OnStartupSec tick after it), S3 switch (the timer is not
# restarted, the next tick runs the new text), S6 surfacing (the floor
# instance is gone and a record waits: the tick fails the unit), withdraw
# (an item disabled while its record waits and the floor is stopped), the
# run-now storm (1000 runs, one without a bus; the drain loses none) and
# run waking a stopped floor. Not covered here: the wake table row by row
# (the package tests), S5 (a cut inside a profile set) and the
# failure-marker hashes of S6 (modules/failure-surfacing.nix).
{ inputs, configurations }:
let
  pkgs = configurations.nas.pkgs;
  inherit (pkgs) lib;
  stub = import "${inputs.dshd}/checks/stub-dsh.nix" {
    inherit pkgs;
    version = "1";
  };
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
in
pkgs.testers.runNixOSTest {
  name = "scheduled-vm";
  globalTimeout = 2400;
  nodes.nas = {
    imports = [
      inputs.dshd.nixosModules.default
      inputs.home-manager-nas.nixosModules.home-manager
    ];
    dshd = {
      enable = true;
      releases.nas.dsh = stub;
    };
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
        "SCHEDULED_FLOOR_INSTANCE=floor"
        "SCHEDULED_VM_NEXT=1"
      ];
    };
  };
  testScript = ''
    import datetime as dt
    import json
    import re
    import shlex

    INBOX = "${inbox}"
    STATE = "/home/tom/.local/state/scheduled"
    STUB_FLOOR = "${stubFloor}"
    # The CLI's defaults, set here as the unit sets them (a login shell may
    # not read Home Manager's session variables).
    CLI = f"env SCHEDULED_INBOX={INBOX} SCHEDULED_FLOOR_INSTANCE=floor"
    CLI_NO_FLOOR = f"env -u SCHEDULED_FLOOR_INSTANCE SCHEDULED_INBOX={INBOX}"
    WAIT = 300


    def tom(command: str, bus: bool = True) -> str:
        \"\"\"A root shell command that runs `command` as tom.\"\"\"
        env = ('rt="$(loginctl show-user tom --property=RuntimePath --value)"; '
               'export XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"; ') if bus else ""
        return "su -l tom -c " + shlex.quote("set -eu; " + env + command)


    def run(command: str, bus: bool = True, timeout: int = WAIT) -> str:
        return nas.succeed(tom(command, bus), timeout=timeout)


    def show(unit: str, prop: str) -> str:
        return run(f"systemctl --user show --property={prop} --value {unit}").strip()


    def tick() -> str:
        \"\"\"Starts the heartbeat service once, as the timer would; its result.\"\"\"
        run("systemctl --user start scheduled-heartbeat.service || true")
        return show("scheduled-heartbeat.service", "Result")


    def records() -> list[str]:
        \"\"\"The heartbeat's records waiting in the inbox (manual runs excluded).\"\"\"
        out = run(f"ls -1 {INBOX} 2>/dev/null || true")
        return [n for n in out.split() if n.endswith(".json") and not n.startswith(".") and "@run~" not in n]


    def manual() -> list[str]:
        out = run(f"ls -1 {INBOX} 2>/dev/null || true")
        return [n for n in out.split() if n.endswith(".json") and "@run~" in n]


    def floor_state() -> str:
        return json.loads(run("dshd get --json floor"))["state"]


    def shift(seconds: int) -> None:
        nas.succeed(f"date -s @$(( $(date +%s) + ({seconds}) ))")


    def last_tick() -> str:
        return json.loads(run(f"cat {STATE}/heartbeat.json"))["lastTick"]


    def journal() -> str:
        return nas.succeed("journalctl --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 || true")


    def quiet() -> None:
        \"\"\"Waits until no tick runs or is queued.\"\"\"
        nas.wait_until_succeeds(tom(
            'test -z "$(systemctl --user list-jobs --no-legend)"'
            ' && test "$(systemctl --user show -p ActiveState --value scheduled-heartbeat.service)" != activating'
        ), timeout=WAIT)


    def hours(iso: str) -> int:
        return int(dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()) // 3600


    def diagnose() -> None:
        \"\"\"What a failed wait for a tick needs: clock, state, ids, timers, the tick journal.\"\"\"
        print(nas.execute(tom(f"date -u; cat {STATE}/heartbeat.json; cat /etc/machine-id; systemctl --user list-timers --all --no-legend;"
                              " systemctl --user show -p Result,ConditionResult,ActiveState scheduled-heartbeat.service") + " 2>&1")[1])
        print(nas.execute("journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=scheduled-heartbeat.service | tail -30")[1])


    def wait_tick(previous: str) -> None:
        try:
            nas.wait_until_succeeds(tom(f"test \"$(jq -r .lastTick {STATE}/heartbeat.json)\" != {shlex.quote(previous)}"), timeout=WAIT)
        except Exception:
            diagnose()
            raise


    def boot() -> None:
        nas.wait_for_unit("multi-user.target")
        nas.wait_for_unit("default.target", "tom")


    def make_floor() -> None:
        \"\"\"A stub web floor named floor, stopped by intent.\"\"\"
        run("DSH_STUB_MODE=web dshd run --bg --json --name floor -- web")
        run("dshd stop --json floor")
        assert floor_state() == "stopped"


    start_all()
    boot()
    # The test drives every tick until S4; the boot tick of OnStartupSec
    # must not fire under it.
    run("systemctl --user stop scheduled-heartbeat.timer")

    with subtest("shape: the NAS's own units, skipped by condition before ~/.agency exists"):
        assert show("scheduled-heartbeat.timer", "UnitFileState") == "enabled", show("scheduled-heartbeat.timer", "UnitFileState")
        assert show("scheduled-heartbeat.service", "Type") == "oneshot"
        assert f"SCHEDULED_INBOX={INBOX}" in show("scheduled-heartbeat.service", "Environment")
        # The unit text, not systemctl's "# /path" header (a store link under Home Manager).
        text = [line for line in run("systemctl --user cat scheduled-heartbeat.timer").splitlines() if not line.startswith("# /")]
        assert not any("/nix/store/" in line for line in text), text
        run("systemctl --user start scheduled-heartbeat.service")
        assert show("scheduled-heartbeat.service", "ConditionResult") == "no"
        assert show("scheduled-heartbeat.service", "Result") == "success"
        run("scheduled --version")

    with subtest("setup: the floor is stopped by intent, one enabled item, one disabled"):
        manifest = json.dumps({"dsh": {"profile": {"bundles": ["@deepseek-ai/dsh-web-app"]}}})
        run(f"mkdir -p ~/.dsh/profiles/web && printf '%s\\n' {shlex.quote(manifest)} > ~/.dsh/profiles/web/package.json")
        make_floor()
        run("install -d -m 0700 ~/.agency")
        run("scheduled new master:hb --cron '0 * * * *' --tz UTC --prompt 'Say ok.'")
        run("scheduled set master:hb enabled true")
        run("scheduled new master:off --cron '0 * * * *' --tz UTC --prompt 'Say ok.'")
        run("scheduled validate --all")
        # Six hours back: room for S8, S1 and S4 below.
        shift(-6 * 3600)

    with subtest("C3.1: the first tick hands off nothing; the floor stays stopped"):
        assert tick() == "success"
        assert records() == [], records()
        assert floor_state() == "stopped"
        first = last_tick()

    with subtest("S8: a clock one hour back hands off nothing and keeps lastTick"):
        shift(-3600)
        assert tick() == "success"
        assert records() == []
        assert last_tick() == first
        assert "clock went back" in journal()

    with subtest("S1: a three-hour gap hands off one record with missed 2 and starts the floor; a repeat makes none"):
        shift(4 * 3600)
        assert tick() == "success"
        made = records()
        assert len(made) == 1, made
        record = json.loads(run(f"cat {INBOX}/{made[0]}"))
        # Three hour marks lie in the gap (four if the test itself crossed one).
        marks = hours(last_tick()) - hours(first)
        assert marks in (3, 4) and record["namespace"] == "master" and record["item"] == "hb", (record, marks)
        assert record["missed"] == marks - 1 and record["cwd"] == "/home/tom" and record["text"] == "Say ok.", record
        assert run(f"stat -c %a {INBOX} {INBOX}/{made[0]}").split() == ["700", "600"]
        # Stopped by intent, and a record waits: the tick starts the floor.
        assert "floor action=start state=stopped waiting=1 result=started" in journal(), journal()
        assert floor_state() == "running"
        assert tick() == "success"
        assert records() == made
        # The disabled item hands off nothing.
        assert not any("~off@" in n for n in made)

    with subtest("S4: power cut; one record at boot, none from the OnStartupSec tick after it"):
        run("systemctl --user start scheduled-heartbeat.timer")
        wait_tick(last_tick())
        # The stub drain's renames to .done/ are not crash-safe (no fsync), so a file
        # it drained may be back in the inbox after the cut; the real Source answers
        # duplicate for it. Count only what the reboot hands off.
        pending = set(records())
        run(f"{STUB_FLOOR} {INBOX}")
        before = last_tick()
        nas.crash()
        # The guest clock comes back at host time, about three hours on.
        nas.start(allow_reboot=True)
        boot()
        wait_tick(before)
        after_boot = records()
        fresh = [n for n in after_boot if n not in pending]
        assert len(fresh) == 1, (after_boot, pending)
        # The floor was running at the cut: after the reboot dshd reads it as a run of a
        # previous boot (previous-boot, or interrupted), a record waits, and the tick starts it.
        this_boot = nas.succeed("journalctl -b --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 || true")
        assert re.search(r"floor action=start state=(previous-boot|interrupted|stopped) waiting=\d+ result=started", this_boot), this_boot
        # The OnStartupSec tick, two minutes after the manager started.
        nas.sleep(150)
        quiet()
        assert records() == after_boot, records()
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

    with subtest("S6: the floor instance is gone and a record waits; the tick fails the unit, nothing is started"):
        # S4's boot tick started the floor; dshd removes only a stopped instance.
        run("dshd stop --json floor")
        run("dshd rm --json floor")
        assert records(), "a record waits"
        assert tick() == "exit-code"
        assert "floor state=not-found" in journal()
        # dshd prints {"instances": [...], "linger": ..., "warnings": [...]}.
        listed = json.loads(run("dshd ls --json"))
        assert listed["instances"] == [], listed

    with subtest("withdraw: an item disabled while its record waits and the floor is stopped loses that record"):
        make_floor()
        waiting = records()
        assert waiting, "S6 left records waiting"
        run("scheduled set master:hb enabled false")
        # Older than the 2 s young-file rule, so this tick reads the edit.
        nas.sleep(3)
        assert tick() == "success"
        assert records() == [], records()
        assert "reason=disabled" in journal() and "withdrawn occurrence=master~hb@" in journal()
        # Nothing waits after the withdrawal: the floor stays stopped.
        assert floor_state() == "stopped"

    with subtest("P9.2: a run-now storm of 1000, one requester without a bus; the drain loses none"):
        # One Node process per request: minutes, not seconds. No floor instance, so
        # the storm tests only the hand-off; the next subtest wakes the floor.
        run(f"seq 999 | xargs -P 8 -I{{}} {CLI_NO_FLOOR} scheduled run master:hb >/dev/null", timeout=1500)
        run(f"{CLI_NO_FLOOR} scheduled run master:hb >/dev/null", bus=False)
        # A disabled item runs by hand: enabled false cancels only scheduled occurrences.
        run(f"{CLI_NO_FLOOR} scheduled run master:off >/dev/null")
        assert len(manual()) == 1001, len(manual())
        assert run(f"ls -A {INBOX}/.tmp | wc -l").strip() == "0"
        kinds = json.loads(run(f"{STUB_FLOOR} {INBOX}"))
        assert kinds == {"manual": 1001}, kinds
        assert manual() == [] and records() == []
        assert floor_state() == "stopped"

    with subtest("run: a manual record wakes a stopped floor once; history lists what the drain received"):
        out = json.loads(run(f"{CLI} scheduled run master:hb --json"))
        assert out["floor"].startswith("floor action=start state=stopped") and out["floor"].endswith("result=started"), out
        assert floor_state() == "running"
        assert len(manual()) == 1
        run(f"{STUB_FLOOR} {INBOX}")
        rows = json.loads(run(f"{CLI} scheduled history master:off --json"))["rows"]
        assert [r["state"] for r in rows] == ["done"] and rows[0]["kind"] == "manual", rows
  '';
}
