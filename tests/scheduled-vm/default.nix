# Scheduled in a NixOS VM (AGENTS.md D52; DESIGN 8.4; PROVE P11.1, P9.2).
#
# One VM `nas`: the dshd module from the dshd input with the upstream stub
# dsh (checks/stub-dsh.nix, DSH_STUB_MODE), a lingering uid-1000 user tom,
# and the real home/scheduled.nix under Home Manager, so the heartbeat
# timer and service under test are the NAS's own text. A specialisation
# `next` changes only the service text. The floor is a stub dsh web
# instance named `floor`, stopped by intent (the morning state, D-11).
#
# Subtests: shape (condition skip before ~/.agency), S8 clock back, S1
# hand-off (3 h gap: one record, missed 2; a repeat makes none), the
# run-now storm (1000 requests, one without a bus; a stub floor drain
# leaves incoming/ empty and loses no request), proposal and paused
# targets, S4 power cut (one record at boot, none from the OnStartupSec
# tick after it), S3 switch (the timer is not restarted, the next tick
# runs the new text) and S6 surfacing (no floor: the tick fails the unit).
# Not covered here, and said so in BUILD-LOG: S2's full wake table (the
# package tests cover it row by row), S3's tick blocked inside dshd start,
# S5 (a cut inside a profile set), S7 (env strip of a floor run) and the
# failure-marker hashes of S6, which need modules/failure-surfacing.nix.
{ inputs, configurations }:
let
  pkgs = configurations.nas.pkgs;
  inherit (pkgs) lib;
  stub = import "${inputs.dshd}/checks/stub-dsh.nix" {
    inherit pkgs;
    version = "1";
  };
  # The stub floor's intake (P9.2): every file in incoming/ must parse as
  # one complete JSON record of a known kind, then it moves to done/. A
  # torn or partial request fails the check.
  stubFloor = pkgs.writers.writePython3 "stub-floor" { } ''
    import json
    import os
    import sys

    spool = sys.argv[1]
    incoming = os.path.join(spool, "incoming")
    done = os.path.join(spool, "done")
    os.makedirs(done, exist_ok=True)
    kinds = {}
    for name in sorted(os.listdir(incoming)):
        path = os.path.join(incoming, name)
        with open(path) as handle:
            record = json.load(handle)
        kind = record["kind"]
        assert kind in ("census", "schedule", "manual"), name
        kinds[kind] = kinds.get(kind, 0) + 1
        os.rename(path, os.path.join(done, name))
    print(json.dumps(kinds))
  '';
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
        "SCHEDULED_VM_NEXT=1"
      ];
    };
  };
  testScript = ''
    import datetime as dt
    import json
    import shlex

    SPOOL = "/home/tom/.agency/state/master/spool"
    STATE = "/home/tom/.agency/state/master"
    STUB_FLOOR = "${stubFloor}"
    WAIT = 300


    def tom(command: str, bus: bool = True) -> str:
        """A root shell command that runs `command` as tom."""
        env = ('rt="$(loginctl show-user tom --property=RuntimePath --value)"; '
               'export XDG_RUNTIME_DIR="$rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"; ') if bus else ""
        return "su -l tom -c " + shlex.quote("set -eu; " + env + command)


    def run(command: str, bus: bool = True, timeout: int = WAIT) -> str:
        return nas.succeed(tom(command, bus), timeout=timeout)


    def status(command: str) -> int:
        code, _ = nas.execute(tom(command), timeout=WAIT)
        return code


    def show(unit: str, prop: str) -> str:
        return run(f"systemctl --user show --property={prop} --value {unit}").strip()


    def tick() -> str:
        """Starts the heartbeat service once, as the timer would; its result."""
        run("systemctl --user start scheduled-heartbeat.service || true")
        return show("scheduled-heartbeat.service", "Result")


    def records() -> list[str]:
        """The occurrence records in incoming/ (census files excluded)."""
        out = run(f"ls -1 {SPOOL}/incoming || true")
        return [n for n in out.split() if n.endswith(".json") and not n.startswith("census@") and "@manual~" not in n]


    def shift(seconds: int) -> None:
        nas.succeed(f"date -s @$(( $(date +%s) + ({seconds}) ))")


    def last_tick() -> str:
        return json.loads(run(f"cat {STATE}/heartbeat.json"))["lastTick"]


    def journal() -> str:
        return nas.succeed("journalctl --no-pager -o cat _SYSTEMD_USER_UNIT=scheduled-heartbeat.service _UID=1000 || true")


    def quiet() -> None:
        """Waits until no tick runs or is queued."""
        nas.wait_until_succeeds(tom(
            'test -z "$(systemctl --user list-jobs --no-legend)"'
            ' && test "$(systemctl --user show -p ActiveState --value scheduled-heartbeat.service)" != activating'
        ), timeout=WAIT)


    def hours(iso: str) -> int:
        return int(dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()) // 3600


    def diagnose() -> None:
        """What a failed wait for a tick needs: clock, state, ids, timers, the tick journal."""
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


    start_all()
    boot()
    # The test drives every tick until S4; the boot tick of OnStartupSec
    # must not fire under it.
    run("systemctl --user stop scheduled-heartbeat.timer")

    with subtest("shape: the NAS's own units, skipped by condition before ~/.agency exists"):
        assert show("scheduled-heartbeat.timer", "UnitFileState") == "enabled", show("scheduled-heartbeat.timer", "UnitFileState")
        assert show("scheduled-heartbeat.service", "Type") == "oneshot"
        # The unit text, not systemctl's "# /path" header (a store link under Home Manager).
        text = [line for line in run("systemctl --user cat scheduled-heartbeat.timer").splitlines() if not line.startswith("# /")]
        assert not any("/nix/store/" in line for line in text), text
        run("systemctl --user start scheduled-heartbeat.service")
        assert show("scheduled-heartbeat.service", "ConditionResult") == "no"
        assert show("scheduled-heartbeat.service", "Result") == "success"
        run("scheduled --version")

    with subtest("setup: the floor is stopped by intent, three workflows, one proposal"):
        manifest = json.dumps({"dsh": {"profile": {"bundles": ["@deepseek-ai/dsh-web-app"]}}})
        run(f"mkdir -p ~/.dsh/profiles/web && printf '%s\\n' {shlex.quote(manifest)} > ~/.dsh/profiles/web/package.json")
        run("DSH_STUB_MODE=web dshd run --bg --json --name floor -- web")
        run("dshd stop --json floor")
        floor = json.loads(run("dshd get --json floor"))
        assert floor["state"] == "stopped", floor
        run("install -d -m 0700 ~/.agency")
        run("scheduled new master:hb --cron '0 * * * *' --tz UTC --prompt 'Say ok.' --by vm")
        run("scheduled new master:paused --cron '0 * * * *' --tz UTC --prompt 'Say ok.' --paused --by vm")
        proposal = json.dumps({
            "name": "Proposed probe", "enabled": False,
            "x-proposal": {"by": "vm", "at": "2026-11-11T00:00:00.000Z", "why": ["test"]},
            "on": {"schedule": [{"cron": "0 6 * * *", "timezone": "UTC"}]},
            "job": {"prompt": "Say ok."},
        })
        run(f"printf '%s\\n' {shlex.quote(proposal)} | scheduled put master:prop --proposal --by vm")
        run("scheduled validate --all")
        # Six hours back: room for S8, S1 and S4 below.
        shift(-6 * 3600)

    with subtest("C3.1: the first tick hands off nothing; the floor stays stopped"):
        assert tick() == "success"
        assert records() == [], records()
        assert any(n.startswith("census@") for n in run(f"ls -1 {SPOOL}/incoming").split())
        assert "action=none state=stopped ending=stopped" in journal(), journal()
        assert json.loads(run("dshd get --json floor"))["state"] == "stopped"
        first = last_tick()

    with subtest("S8: a clock one hour back hands off nothing and keeps lastTick"):
        shift(-3600)
        assert tick() == "success"
        assert records() == []
        assert last_tick() == first
        assert "clock went back" in journal()

    with subtest("S1: a three-hour gap hands off one record with missed 2; a repeat makes none"):
        shift(4 * 3600)
        assert tick() == "success"
        made = records()
        assert len(made) == 1, made
        record = json.loads(run(f"cat {SPOOL}/incoming/{made[0]}"))
        # Three hour marks lie in the gap (four if the test itself crossed one).
        marks = hours(last_tick()) - hours(first)
        assert marks in (3, 4) and record["workflow"] == "master:hb" and record["missed"] == marks - 1, (record, marks)
        assert tick() == "success"
        assert records() == made
        # The paused workflow and the proposal hand off nothing.
        assert not any("paused" in n or "prop" in n for n in made)

    with subtest("S4: power cut; one record at boot, none from the OnStartupSec tick after it"):
        run("systemctl --user start scheduled-heartbeat.timer")
        wait_tick(last_tick())
        # The stub floor's renames to done/ are not crash-safe (no fsync), so a file
        # it drained may be back in incoming/ after the cut; the real floor keeps one
        # row per occurrence. Count only what the reboot hands off.
        pending = set(records())
        run(f"{STUB_FLOOR} {SPOOL}")
        before = last_tick()
        nas.crash()
        # The guest clock comes back at host time, about three hours on.
        nas.start(allow_reboot=True)
        boot()
        wait_tick(before)
        after_boot = records()
        fresh = [n for n in after_boot if n not in pending]
        assert len(fresh) == 1, (after_boot, pending)
        # DESIGN 6.2 as written: after a reboot dshd reads the floor `previous-boot`
        # (stop intent is not kept across boots), and something waits, so the tick
        # starts it. A finding for the spec, asserted so a change is seen.
        assert "floor action=start state=previous-boot" in journal(), journal()
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

    with subtest("S6: no floor; the tick fails the unit, nothing is started"):
        # S4's boot tick started the floor; dshd removes only a stopped instance.
        run("dshd stop --json floor")
        run("dshd rm --json floor")
        assert tick() == "exit-code"
        assert "floor error=not-found" in journal()
        assert json.loads(run("dshd ls --json")) in ([], {"instances": []})

    with subtest("P9.2: a run-now storm of 1000, one requester without a bus, proposal refused"):
        # One Node process per request, while ticks run back to back: minutes, not seconds.
        # The floor S6 removed comes back, stopped by intent, so the storm's ticks succeed.
        run("DSH_STUB_MODE=web dshd run --bg --json --name floor -- web")
        run("dshd stop --json floor")
        run(f"{STUB_FLOOR} {SPOOL}")
        run("seq 999 | xargs -P 8 -I{} scheduled run master:hb --by storm >/dev/null", timeout=1500)
        run("scheduled run master:hb --by nobus >/dev/null", bus=False)
        assert status("scheduled run master:prop --by storm") == 1
        # A paused workflow still runs by hand (DESIGN 7.3: disabled cancels only scheduled runs).
        run("scheduled run master:paused --by storm >/dev/null")
        manual = [n for n in run(f"ls -1 {SPOOL}/incoming").split() if "@manual~" in n]
        assert len(manual) == 1001, len(manual)
        quiet()
        assert run(f"ls -A {SPOOL}/tmp 2>/dev/null | wc -l").strip() == "0"
        # Unlimited starts: the storm's wakes never fail the unit.
        assert show("scheduled-heartbeat.service", "Result") == "success"
        kinds = json.loads(run(f"{STUB_FLOOR} {SPOOL}"))
        assert kinds.get("manual") == 1001, kinds
        assert run(f"ls -A {SPOOL}/incoming | wc -l").strip() == "0"
  '';
}
