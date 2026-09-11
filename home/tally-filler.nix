{
  lib,
  osConfig,
  pkgs,
  ...
}:
# tally-filler — the filler lane's clock: one user timer that wakes one E1
# replay pass, on the coordinator, at the academic drain's own cadence.
#
# UNIT: U-D18 DF-FILLER-TIMER. ISSUE: dotfiles#321. SPEC:
# /home/tom/sept7/plan/TALLY-SPEC-2026-09-06.md §4.4 (the filler-lane contract),
# §5.3 item 4 (what runs unattended), handoff DoD F, and
# ~/research-methods/DECISIONS.md D-B10 (the two fillers alternate) and
# D-U-E1LOOP-7 (`--all` "is what U-D18's timer calls").
# DOC: docs/local-ai/tally-filler-timer.md.
#
# WHAT THIS FILE IS, IN ONE SENTENCE. A clock and nothing else: the timer wakes
# the filler pass, and every decision about whether an item may run is taken by
# the kernel's admission on `gpu-coordinator` — this module admits nothing,
# ranks nothing, and holds no policy. "The timer only wakes the uplink's filler
# pass, the kernel admits" is the card's own sentence and it is the whole
# division of labour here.
#
# WHAT THE FILLER VERB IS, AND WHY IT IS NOT A VERB OF apps/uplink. The card
# says "the uplink's filler verb". The LAKE's uplink, at the rev this repository
# pins (`tally-lake` = tally-ts-sdk a233c30), exports no such verb: its CLI has
# `--parse-only`, `--replay-only`, `--drain-only` and the default wake, and the
# string "filler" does not occur anywhere in that input (MEASURED 2026-09-07,
# `grep -rl filler <store path>` → no hit). The lane's verb is named instead by
# a captured ruling — ~/research-methods/DECISIONS.md D-U-E1LOOP-7, "`--all` is
# the lane's verb over the whole eligible population and is what U-D18's timer
# calls" — so the ExecStart below is
#
#   bash %h/research-methods/tools/e1-loop.sh --all
#
# and that script is the one that walks `cards/e1-sample.tsv`'s eligible rungs,
# one item at a time. See DECISIONS.md (U-D18) for the line and its consequence.
#
# WHY THE VERB IS AN OUT-OF-STORE PATH. The register (`~/research-methods`) is
# LOCAL by ruling — ~/research-methods/DECISIONS.md D-B12, "the register stays
# local" — so it is not, and must not become, a flake input of this repository.
# Naming its script through `%h` is the same seam home/seat-feeder.nix already
# uses for the one sanctioned credential reader
# (`TALLY_STAMP_RECEIPT=%h/research-methods/bin/stamp-receipt.py`): the estate
# points at the register, the register is never copied into the store. A missing
# script is therefore a LEGIBLE failure — the unit exits non-zero naming the
# path — and deliberately not a `ConditionPathExists=` that would make an absent
# lane a silent no-op.
#
# HOW THE TWO FILLERS ALTERNATE (D-B10). D-B10 rules that "the two fillers (E1
# replay, academic drain) alternate by round-robin on `gpu-coordinator`". Two
# mechanisms carry that here, and neither of them is in this file's gift alone:
#
#   1. CADENCE. This timer's period is the DRAIN's own period, not a number
#      chosen here: `tally-drain.timer` is declared with
#      `OnUnitActiveSec = "5min"` (MEASURED in the rendered coordinator config
#      and in the installed unit file, 2026-09-07), so over any five minutes
#      each of the two fillers gets exactly one wake and neither can crowd the
#      other out. flake.nix's `tally-filler-topology` check asserts the two
#      values are EQUAL rather than asserting a literal, so a drift in the
#      upstream drain turns this check red instead of silently ending the
#      round-robin.
#   2. SERIALISATION ON THE GPU. Cadence alone cannot keep two tenants off one
#      device. What does is the lane's own gate: `tools/e1-loop.sh` waits for
#      the inference server to be idle before it dispatches an item, and
#      never issues a second concurrent model request (its step 4, and
#      E1-LOOP's own non-goal). So whoever holds the model finishes; the other
#      takes the next turn. That gate is a read of a status endpoint made by
#      the lane, never by this unit.
#
# NON-GOALS, AS BYTES. "The timer never calls the inference server directly;
# never stops a serve." Nothing in the rendered unit below names the server,
# its port, or any stop/restart of a serve — asserted in both directions by the
# flake check and by tools/u-d18-filler-timer-oracle.sh. In particular this
# module does NOT set `E1_PROBE_URL`: the lane's idle probe stays the lane's
# own default, so the endpoint is not even a string this unit carries.
#
# RULE 9 (nothing hand-installed stays so). This unit is declared here before it
# has ever run by hand; there is no ~/.config/systemd/user/tally-filler* pair to
# disable and delete first, and there must never be one. The oracle's proof that
# the timer RUNS is a TRANSIENT `systemd-run --user --on-calendar` unit under a
# different name (`tally-filler-probe`), which systemd garbage-collects.
#
# WHAT THIS FILE DOES NOT DO. It switches nothing (U-D19 owns the coordinator
# switch, ~/research-methods/DECISIONS.md D-B15; DEFERRED.md DF-U-D18-1). It
# writes nothing under ~/.local/state — not branch (a)'s ~/.local/state/tally/,
# not the rewrite's ~/.local/state/tally-rewrite/ — because the filler lane's
# whole state is the register's own git tree (its receipts, its
# `cards/e1-results.tsv` row, and its kept replay worktree). It sets no
# anti-starvation number: TL-10 is unset and D-B10's age-based promotion belongs
# to the release station, not to a clock (DEFERRED.md DF-U-D18-2). And it gives
# the UPLINK no schedule: `home/tally-uplink.nix` still renders with no
# `Install` section, which is what DF-U-D14-4 asked this unit to discharge —
# with a timer of its own, never by installing the uplink.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # The register checkout and the lane's verb inside it. `%h` and not a literal
  # /home/tom: this is a user unit, so the two are the same value, and the
  # specifier keeps the module free of one estate's home directory.
  registerRoot = "%h/research-methods";
  fillerScript = "${registerRoot}/tools/e1-loop.sh";
  fillerSelector = "--all";

  # The lake checkout the lane sources its node toolchain from
  # (`$E1_LAKE/scripts/node-env.sh`, then `apps/evaluator/bin/evaluate.mjs` for
  # the mechanical rerun). Spelled here rather than left at the script's own
  # default for the reason modules/tally-b.nix gives one bus over: the unit
  # then SAYS what it runs against instead of inheriting it.
  lakeRoot = "%h/mecattaf/tally-ts-sdk";

  # The drain's period, MEASURED, and the reason this string is "5min" and not a
  # taste: `tally-drain.timer` (the other filler of D-B10) is declared
  # `OnUnitActiveSec = "5min"` — MEASURED both in the rendered coordinator
  # config and in the installed unit file on the coordinator, 2026-09-07. It is
  # spelled here in the drain's OWN units, byte for byte, so flake.nix's
  # `tally-filler-topology` check can assert the two are the same string; "300s"
  # would be the same duration and a different byte, and the equality — not the
  # number — is what keeps the round-robin from drifting.
  fillerPeriod = "5min";
  timerAccuracySeconds = 1;

  # A user unit inherits no interactive PATH. The lane's scripts name their own
  # preconditions — e1-loop.sh refuses without `curl date git jq journalctl
  # python3 sha256sum`, run-e1-worker.sh without `awk bwrap curl date git jq
  # sha256sum timeout` — so every one of those is pinned to a store path here.
  #
  # The two profile directories come LAST and are not decoration:
  #   /etc/profiles/per-user/tom/bin  run-e1-worker.sh execs the local arm as
  #                                   /etc/profiles/per-user/tom/bin/pi, an
  #                                   absolute path in the register's own
  #                                   script; the entry keeps anything it
  #                                   reaches for by name resolvable too.
  #   /run/current-system/sw/bin      a frontier receipt's oracle argv is
  #                                   rerun verbatim by the lane's evaluator
  #                                   step, and this estate's oracles are
  #                                   `nix ...` argvs. Pinning a second nix
  #                                   into a filler unit would be this
  #                                   repository deciding which nix an
  #                                   unrelated repository's oracle runs.
  # node is deliberately absent: the lane applies the lake's own recorded
  # interpreter through `$E1_LAKE/scripts/node-env.sh` and refuses if it cannot.
  # `bin/register calibrate` imports numpy lazily after a verdict. Pinning the
  # bare interpreter made every completed replay fail at that last step even
  # though Tom's later profile Python happened to carry numpy (#346); the unit
  # must carry its own dependency instead of relying on PATH fall-through.
  fillerPython = pkgs.python3.withPackages (ps: [ ps.numpy ]);
  fillerPath =
    lib.makeBinPath [
      pkgs.bash
      pkgs.bubblewrap
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      fillerPython
      pkgs.systemd
    ]
    + ":/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin";
in
# Asserted over LITERALS here (a top-level assert that forced `config` would
# recurse — U-D14's finding, DECISIONS.md (U-D14) (7)); the invariants over the
# RENDERED unit live in flake.nix's `tally-filler-topology` check.
#
# LITERALS ONLY, and that is not a style choice: a top-level assert that forces
# `pkgs` (which `fillerPath` does) is evaluated while the module system is still
# merging and dies "infinite recursion encountered" — MEASURED here on the first
# draft of this file, the same class of failure U-D14 hit with `config`. So the
# non-goals over the PATH ("never calls the server", "never stops a serve") are
# asserted in flake.nix over the rendered unit, where they are strictly stronger
# anyway: there they cover ExecStart and Environment together.
assert fillerPeriod != "";
assert lib.hasSuffix "/tools/e1-loop.sh" fillerScript;
assert lib.hasInfix "/research-methods/" fillerScript;
assert fillerSelector == "--all";
{
  systemd.user.services.tally-filler = lib.mkIf isCoordinator {
    Unit = {
      Description = "tally filler lane: one E1 replay pass through the kernel's admission on gpu-coordinator";
      # X- keys are systemd's own extension space and are ignored by the
      # manager; they are read by tools/u-d18-filler-timer-oracle.sh so the
      # unit's own declaration says which level it is, which peer it alternates
      # with, and which verb it calls — rather than the oracle re-deriving all
      # three from prose.
      X-TallyLevel = "filler";
      X-TallyPeerTimer = "tally-drain.timer";
      X-TallyVerb = "e1-loop.sh ${fillerSelector}";
      X-TallyPeriod = fillerPeriod;
    };
    Service = {
      # One pass per invocation. There is no loop in this unit — the timer is
      # the clock, exactly as it is for home/seat-feeder.nix's instruments. A
      # missed wake is a gap, and the next wake closes it.
      Type = "oneshot";

      # The filler is the LOWEST level (§4.4.1), so it never competes with the
      # work it fills around. Niceness is NOT the preemption mechanism —
      # preemption is the kernel answering `NotYet {preempt}` to a non-filler
      # proposal and the holder yielding its lease within one item — but a
      # filler that fights for the CPU with a level-1 worker would be wrong
      # even so.
      Nice = 19;
      IOSchedulingClass = "idle";

      Environment = [
        "PATH=${fillerPath}"
        "E1_LAKE=${lakeRoot}"
      ];

      ExecStart = "${pkgs.bash}/bin/bash ${fillerScript} ${fillerSelector}";

      # NO start timeout, deliberately, and this is the one systemd default
      # this unit must override. §4.4.2 bounds an ITEM by
      # `runtime_cap_seconds`, which the lane enforces itself per item; a
      # manager-side deadline over the whole pass would SIGTERM the unit
      # mid-item and cost more than the one item a preemption is allowed to
      # cost. The lane's own `abort_on.consecutive_crash: 2` (§4.4.6) is what
      # stops a cold-load crash loop, not a clock.
      TimeoutStartSec = "infinity";

      # No Restart=: a failed pass is a gap the next wake closes, and a
      # restart loop on a GPU lane would be exactly the crash loop
      # `abort_on.consecutive_crash` exists to name.
    };
  };

  systemd.user.timers.tally-filler = lib.mkIf isCoordinator {
    Unit.Description = "tally filler lane wake (${fillerPeriod} — tally-drain.timer's own cadence, D-B10 round-robin)";
    Timer = {
      # The drain's own shape, one lane over: a delay after the timer is
      # ARMED, then a period from each activation. OnActiveSec rather than
      # OnBootSec because what arms this timer is a switch, not a boot, and a
      # box that has been up for a day should still get a settling period
      # before its first GPU pass rather than an immediate one.
      OnActiveSec = fillerPeriod;
      OnUnitActiveSec = fillerPeriod;
      AccuracySec = "${toString timerAccuracySeconds}s";
      Unit = "tally-filler.service";
      # This is a monotonic tick, not a wall-clock backlog: no Persistent
      # catch-up is declared. A box that was off owes the lane nothing — the
      # backlog is `cards/e1-sample.tsv`, and it is still there.
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
