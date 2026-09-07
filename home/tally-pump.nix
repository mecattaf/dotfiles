{
  lib,
  osConfig,
  pkgs,
  ...
}:
# tally-pump — the RELEASE STATION's clock: one user timer that wakes one pump
# tick on the coordinator, every five minutes, and nothing else.
#
# UNIT: FIX-E11 (spec id `pump-has-no-scheduler`). ISSUE: dotfiles#350.
# DECIDED: ~/research-methods/DECISIONS.md D-E24 (orchestrator E's fix round),
# D-B89 (exactly one pump). SIBLING HALF: the codex-lane commit that adds
# `pump.sh --once` and tests/probe-FIX-E11.sh.
#
# WHY THIS FILE EXISTS, IN ONE MEASUREMENT. The release station had no owner.
# MEASURED 2026-09-07 on the coordinator: `tail -60 pump.log` ended
#
#   PUMP tick136: quiet 1/2
#   PUMP tick137: quiet 2/2
#   PUMP: quiescent — nothing running, nothing releasable
#
# because pump.sh BREAKS out of its `while` loop after two quiescent ticks;
# `cat pump.pid` -> 3519550 and `ps -p 3519550 -o pid,etime,cmd` printed only
# its header (rc 1) — a stale pid for a pump dead since 21:42 — while
# `pgrep -af 'bash pump.sh'` matched only the grep itself. Nothing restarted it:
# `grep -rl 'codex-lane\|pump.sh' /etc/systemd /run/systemd ~/.config/systemd`
# had NO hits, `systemctl --user cat 'pump*'` and `systemctl cat 'pump*'` were
# empty, and `crontab -l` -> "crontab: command not found". Every start on record
# is a typed line (HANDOFF-E:183 `setsid -f bash pump.sh >> pump.log 2>&1`,
# FACTORY-LEDGER-2026-09-07.md:32 the same with `env MAXW=2`). So the factory's
# release step depended on a human being awake, which is the one thing it is
# built not to need. This timer is that owner.
#
# WHAT THIS FILE IS, IN ONE SENTENCE. A clock and nothing else — the same
# division of labour home/tally-filler.nix states for the filler lane: the timer
# wakes ONE tick, and every decision inside that tick (what to harvest, what to
# grade, on which seat, what to repair, what to release, and whether the seat
# budget allows it at all) belongs to the lane's own scripts. This module admits
# nothing, ranks nothing, routes nothing and holds no policy.
#
# WHY `--once` AND NOT THE LOOPING FORM UNDER A UNIT. A `Type=simple` unit
# holding the 60-second loop would have to be Restart=always, which turns the
# lane's own crash into a hot loop, and it would make the human's watchable
# `setsid -f bash pump.sh` form a SECOND pump. `--once` inverts that: the tick
# is the unit of work (it is idempotent by construction — harvest, reconcile,
# seat pick, evaluators, repair station, release), the manager owns the cadence,
# a missed wake is a gap the next wake closes, and rc 0 on a quiescent lane
# means a quiet factory never reads as a failed unit. The looping form still
# exists, unchanged, and the two can never overlap: `pump.sh` writes and honours
# `pump.pid` (D-B89), so whichever starts second refuses at rc 3 with
# "PUMP: another pump holds <pid>" and this unit records that skip as a failure
# of the tick — which is the honest reading, because that tick did not run.
#
# WHY THE VERB IS AN OUT-OF-STORE PATH. The lane (`~/sept7/plan/codex-lane`) is
# a local working tree by construction: it holds the live manifest's decisions,
# its runs/, its evals/ and its results.json, and it is not — and must not
# become — a flake input of this repository. Naming it through `%h` is exactly
# the seam home/tally-filler.nix uses for `%h/research-methods/tools/e1-loop.sh`
# and home/seat-feeder.nix for its one sanctioned credential reader. A missing
# script is therefore a LEGIBLE failure (the unit exits non-zero naming the
# path), deliberately not a `ConditionPathExists=` that would make an absent
# lane a silent no-op.
#
# WHY MAXW=2 AND WHY IT IS SET HERE. `pump.sh` defaults to `MAXW=14` concurrent
# workers/evaluators; both typed starts on record set `MAXW=2`, because the
# seat budget — not the machine — is the scarce resource (only seat cc2 exists;
# cc3 is barred). The number is spelled in `Environment=` rather than by an
# `env(1)` wrapper in ExecStart: the same value, one fewer process, and the
# idiom tally-filler.nix already uses for `E1_LAKE`. It is asserted over the
# rendered unit by flake.nix's `tally-pump-topology`, so a drift is red.
#
# WHERE THE OUTPUT GOES. `append:` to the lane's own `pump.log`, so the tick
# log stays ONE file across both forms — the typed `>> pump.log` form and this
# unit — and `tail -f pump.log` remains the way to watch the station. (Specifier
# expansion applies to these paths: `systemd-analyze --user verify` accepts the
# rendered pair, MEASURED 2026-09-08.)
#
# NON-GOALS, AS BYTES, asserted in flake.nix over the rendered unit: it never
# names llama-swap, port 9292 or any unload/restart of a serve (the pump does
# not touch the GPU lane); it writes nothing under ~/.local/state (neither
# branch (a)'s ~/.local/state/tally/ nor the rewrite's ~/.local/state/tally-
# rewrite/ — the station's whole state is the lane's own files); it declares no
# system-bus twin; and it is COORDINATOR ONLY (the worker holds no seat, no
# manifest and no lane, so a pump there would be a second release station).
#
# RULE 9 (nothing hand-installed stays so). There is no
# ~/.config/systemd/user/tally-pump* pair to disable and delete first (MEASURED:
# the grep above found none anywhere), and there must never be one.
#
# WHAT THIS FILE DOES NOT DO. It switches nothing: like every unit in this
# repository it lands live at the next coordinator switch, and until then the
# station stays a typed line. It does not restart, stop or enable llama-swap or
# any other service. And it sets no policy about WHICH units get released — that
# is next.py's, through the manifest and the measured seat headroom.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # The lane and its verb. `%h` and not a literal /home/tom: this is a user
  # unit, so the two are the same value, and the specifier keeps the module free
  # of one estate's home directory.
  laneRoot = "%h/sept7/plan/codex-lane";
  pumpScript = "${laneRoot}/pump.sh";
  pumpSelector = "--once";
  pumpLog = "${laneRoot}/pump.log";

  # The concurrency cap, spelled as the two typed starts on record spell it.
  maxWorkers = "2";

  # Every five minutes on the wall clock. OnCalendar (not OnUnitActiveSec)
  # because the release station's cadence should not drift with the duration of
  # a tick that happened to launch four workers: a tick is short, the interval
  # is what matters, and a wall-clock schedule is the one a human can predict
  # when reading pump.log next to `date`.
  pumpCalendar = "*:0/5";
  timerAccuracySeconds = 1;

  # A user unit inherits no interactive PATH, and this lane's tick shells out to
  # more than most: python3 (next.py, harvest.py, seat.py, repair.py,
  # merge-reconcile.py, codex-window.py), git and gh (merge-reconcile reads the
  # world through `gh pr view` and `git branch --contains`; launch.sh renders a
  # worker's task from `gh issue view`), coreutils/gnugrep/gnused/gawk/findutils
  # for the tick's own plumbing, jq for the launcher, util-linux for the
  # `setsid` a codex launch uses, and procps for process inspection.
  #
  # The two profile directories come LAST and are not decoration:
  #   /etc/profiles/per-user/tom/bin  launch.sh execs the harnesses by name
  #                                   (claude, codex, pi); they live here.
  #   /run/current-system/sw/bin      a receipt's oracle argv is rerun verbatim
  #                                   by an evaluator, and this estate's oracles
  #                                   are `nix ...` argvs. Pinning a second nix
  #                                   into this unit would be this repository
  #                                   deciding which nix an unrelated
  #                                   repository's oracle runs.
  # No numpy-capable python is pinned because the lane needs none: no script in
  # the lane imports numpy (MEASURED 2026-09-08, `grep -n numpy *.py` -> no hit),
  # exactly as home/tally-filler.nix pins the plain pkgs.python3.
  pumpPath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gawk
    pkgs.gh
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.procps
    pkgs.python3
    pkgs.systemd
    pkgs.util-linux
  ]
  + ":/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin";
in
# LITERALS ONLY in these asserts, and that is not a style choice: a top-level
# assert that forces `pkgs` (which `pumpPath` does) is evaluated while the module
# system is still merging and dies "infinite recursion encountered" — U-D14's
# finding, repeated in home/tally-filler.nix's own comment. The invariants over
# the RENDERED unit live in flake.nix's `tally-pump-topology` check, where they
# are strictly stronger anyway (they cover ExecStart and Environment together).
assert pumpSelector == "--once";
assert lib.hasSuffix "/codex-lane/pump.sh" pumpScript;
assert maxWorkers != "";
assert pumpCalendar != "";
{
  systemd.user.services.tally-pump = lib.mkIf isCoordinator {
    Unit = {
      Description = "tally release station: one pump tick (harvest, grade, repair, release) on gpu-coordinator";
      # X- keys are systemd's own extension space, ignored by the manager and
      # read by the topology check and by a human running `systemctl --user cat`:
      # the unit says which station it is, which verb it calls and at what
      # cadence, rather than leaving all three to prose.
      X-TallyStation = "release";
      X-TallyVerb = "pump.sh ${pumpSelector}";
      X-TallyCalendar = pumpCalendar;
      X-TallyMaxWorkers = maxWorkers;
    };
    Service = {
      # One tick per invocation. There is no loop in this unit and none in the
      # process it starts: `--once` returns after a single tick.
      Type = "oneshot";

      Environment = [
        "PATH=${pumpPath}"
        "MAXW=${maxWorkers}"
      ];

      ExecStart = "${pkgs.bash}/bin/bash ${pumpScript} ${pumpSelector}";

      # One log for both forms, appended exactly as the typed start appends it.
      StandardOutput = "append:${pumpLog}";
      StandardError = "append:${pumpLog}";

      # A tick launches workers and evaluators as detached processes and then
      # returns; it does not wait for them. Ten minutes is therefore two
      # periods of headroom over anything a tick legitimately does (its longest
      # step is a `gh`/`git` read), and a tick still wedged after that is a
      # fault worth SIGTERMing rather than one worth carrying into the next
      # wake — the opposite trade from the filler's `TimeoutStartSec=infinity`,
      # which bounds a GPU item that must not be cut mid-flight.
      TimeoutStartSec = "10min";

      # No Restart=: a failed tick is a gap the next wake closes five minutes
      # later, and a restart loop over a station that launches paid workers is
      # exactly the failure mode this unit exists to end.
    };
  };

  systemd.user.timers.tally-pump = lib.mkIf isCoordinator {
    Unit.Description = "tally release station wake (every 5 min, wall clock — FIX-E11, dotfiles#350)";
    Timer = {
      OnCalendar = pumpCalendar;
      # A tick is a TICK, not a backlog: a box that was off owes the station
      # nothing, because the state it would catch up on (runs/, evals/,
      # results.json, the manifest) is all still there and the next wake reads
      # it. Persistent=true would fire a burst of catch-up ticks at switch time,
      # each able to launch workers. Declared false rather than omitted so the
      # unit SAYS so.
      Persistent = false;
      AccuracySec = "${toString timerAccuracySeconds}s";
      Unit = "tally-pump.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
