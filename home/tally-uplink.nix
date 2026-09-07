{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
# tally-uplink — the LAKE's box-side loop, on the coordinator's USER bus.
#
# UNIT: U-D14 DF-LAKE-INPUT. ISSUE: dotfiles#317. SPEC:
# /home/tom/sept7/plan/TALLY-SPEC-2026-09-06.md §2.1 Deliverable, §2.2b (the
# wake mechanism and the seven routes), §7 amendment 7 (lane D widened by DoD
# F). DOC: docs/local-ai/tally-uplink-input.md.
#
# WHAT THIS FILE IS. The dotfiles half of the `tally-lake` input, and it is ONE
# home-manager module, the same motion home/tally.nix performs for the live
# daemon (the card's exemplar): import the upstream module the input exports,
# then set its options for this estate on the coordinator only. Everything the
# uplink DOES is the lake's own code — probe every row of the rows file, POST
# the reading, pull /proposals, admit over the kernel socket, POST /outcomes,
# execute under lease, mirror the chain, re-arm the plan — and none of it is
# re-implemented here.
#
#   imports = [ inputs.tally-lake.homeManagerModules.tally-uplink ];
#
# W-03 exported that module (lake commit c29fdfb) precisely so this file would
# be an import and a set of options rather than a second copy of the unit's
# shape; the lake's own DEFERRED.md hands the wiring over by name —
# "[OPERATOR] The rows file the box actually probes … naming it is U-D14's
# module and Tom's switch" and "[SCOPE] The NixOS module, the systemd system
# unit and the switch".
#
# USER BUS, NOT SYSTEM BUS, AND WHY THAT IS NOT A CHOICE. The lake's module
# declares `systemd.user.services.tally-uplink`; it ships no NixOS module (its
# card's non-goal) and this unit does not invent one. The uplink is tom's own
# loop: it reads the token from tom's state tree, talks to the served kernel
# over a 0600 socket in that same tree, and runs admitted argv as tom. Its twin
# on the system bus is `tally-kernel.service` (U-D13, modules/tally-b.nix), and
# the two never meet except over that socket.
#
# THE STATE ROOT IS THE REWRITE'S. Every path below is under
# ~/.local/state/tally-rewrite/ — the token, the socket, the chain, the uplink's
# own outbox. Nothing here reads or writes ~/.local/state/tally/, branch (a)'s
# live root: the served kernel refuses it by name (tally
# crates/tally-kernel/src/ledger.rs:31-35) and the seat feeders
# (home/seat-feeder.nix) already keep the two estates apart. The assert below
# makes that a red eval rather than a boot-time discovery.
#
# THE TOKEN IS A PATH, NEVER A VALUE. `tokenFile` names
# ~/.local/state/tally-rewrite/lake-token and nothing in this repository writes,
# reads, prints or stores its contents — not in flake.nix, not in the unit, not
# in the nix store, not in a tmpfiles rule that would create it empty. The lake
# reads it into an Authorization header and every diagnostic goes through its
# own `redact` (apps/uplink/src/lake.mjs); an absent file raises a LakeError
# naming the path, which is a legible failure and not a silent no-token run.
# Writing the file is TL-13's act and Tom's (DEFERRED.md DF-U-D14-2).
#
# NOT A SWITCH — BUT, SINCE FIX-E12, A CLOCK. This module declares the unit;
# only U-D19's coordinator switch installs it (DEFERRED.md DF-U-D14-1). What it
# now also declares is the WAKE, because for seven hours nothing on the box
# could deliver one.
#
# MEASURED 2026-09-07/08 on the coordinator (spec id `uplink-has-no-trigger`,
# issue dotfiles#351, DECIDED ~/research-methods/DECISIONS.md D-E24):
# `systemctl --user list-units --failed` → exactly one unit, tally-uplink.service,
# 'Active: failed (Result: exit-code) since Mon 2026-09-07 15:56:31 CEST; 7h ago';
# `systemctl --user show tally-uplink.service -p TriggeredBy -p WantedBy
# -p RequiredBy -p Wants` → all four EMPTY; `systemctl --user cat
# tally-uplink.timer` → rc 1 'No files found'; `list-dependencies --reverse` →
# the single line 'tally-uplink.service'; `list-timers --all` → 16 timers, none
# of them this one. The trigger this file deferred to "U-D18's filler-lane
# timer" (DF-U-D14-4) was never wired: `grep -c uplink
# ~/research-methods/tools/e1-loop.sh` → 0, rc 1. A unit with `wakes = 1`, no
# `Install`, no timer and no reverse dependency runs exactly as many times as a
# human types `systemctl --user start`, which is the one thing this estate is
# built not to need. So DF-U-D14-4 is discharged HERE, by a timer of the
# uplink's own, and not by installing the service.
#
# THE DIVISION OF LABOUR IS UNCHANGED. The timer is a clock and nothing else —
# the same shape home/tally-filler.nix and home/tally-pump.nix state for their
# lanes. It adds no scheduling logic to the uplink (the card's non-goal, "the
# lake proposes, the door answers"): the SERVICE still renders with `wakes = 1`,
# `Type=oneshot` and no `Install` section of its own — one wake per invocation,
# never a loop this file authorises — and the only instant the uplink itself
# waits for is still the `next_wake_at` the lake handed back. A socket event or
# a verdict may still start it; this timer only guarantees that something does.
#
# WHY THE MONOTONIC FORM AND NOT A WALL CLOCK. `OnUnitInactiveSec` measures the
# period from the moment the previous run went INACTIVE — including the moment
# it went inactive by FAILING — so wakes can never pile up behind a run that is
# failing fast or hanging under its timeout: there is always a full quiet period
# between the end of one wake and the start of the next. An `OnCalendar = *:0/5`
# would instead keep marking the wall clock through a long or repeatedly failing
# run and start the next one the instant the mark passed. That matters right now
# and not hypothetically: the uplink exits 1 against the deployed lake's 5xx
# until the `tally-lake` pin is bumped and the switch lands (FIX-E04), so this
# timer's first job is to fail patiently, once every five minutes, instead of
# hot-looping over a red dependency. `OnActiveSec` gives the same period as the
# FIRST delay after the timer is armed — the filler's own reasoning (what arms
# this timer is a switch, not a boot, and the base for `OnUnitInactiveSec` does
# not exist until the unit has run once), so a switch does not fire a wake in
# the same second it lands. `Persistent = false`, declared rather than omitted
# so the unit says so: a box that was off owes the lake nothing, because the
# state a catch-up burst would work through (the outbox, the ledger, the lake's
# own record of `last_seq`) is all still there and the next wake reads it, and a
# burst of wakes is exactly what a `wakes = 1` unit must never be given.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # The wake period, and the accuracy of the wake. Five minutes IS the drain's
  # own declared cadence on this box (MEASURED in the rendered coordinator
  # config: `systemd.user.timers.tally-drain.Timer.OnUnitActiveSec` = "5min",
  # which home/tally-filler.nix already ties its lane to), so the box keeps ONE
  # rhythm for the rewrite's periodic work instead of three. The literal lives
  # here because a top-level assert may not force `config`; the EQUALITY with
  # the drain's declaration is asserted over the rendered timer in flake.nix's
  # `tally-uplink-topology`, so a cadence drift on either side is red rather
  # than silent.
  uplinkPeriod = "5min";
  timerAccuracySeconds = 1;

  # The rewrite's own state root, spelled absolute from home.homeDirectory
  # rather than left at the lake module's `%h` defaults. Same value (this is a
  # user unit, so `%h` IS /home/tom) and one reason: the rendered ExecStart then
  # SAYS the paths it runs against, so the topology check and the test script
  # read them without a specifier-expansion step of their own. This is
  # modules/tally-b.nix's stated reasoning for the system side ("spelling them
  # here means the unit says what it runs against instead of inheriting it from
  # $HOME"), one bus over.
  # Held as a SUFFIX of home.homeDirectory and only joined to it lazily: a
  # top-level `assert` that forced `config` would recurse (home-manager has no
  # `assertions` option of the kind NixOS gives modules/tally-b.nix, MEASURED:
  # no `options.assertions` anywhere in the pinned home-manager's modules/), so
  # the invariants below are asserted over literals here and over the RENDERED
  # unit in flake.nix's `tally-uplink-topology` check, which is where a
  # home-manager module's eval-time guard lives in this repository.
  stateSuffix = ".local/state/tally-rewrite";
  rewriteState = "${config.home.homeDirectory}/${stateSuffix}";

  # The rows file the uplink probes, row by row: the PINNED kernel's own
  # docs/rows.md, out of the store — `${inputs.tally-b}/docs/rows.md`. Not the
  # live checkout at /home/tom/mecattaf/tally, which a `git checkout` could move
  # under the unit without a review anywhere. This makes the rows the uplink
  # probes and the kernel it probes them against ONE pin: both come from the
  # same `tally-b` rev flake.nix names, so they cannot drift apart in silence.
  #
  # MEASURED 2026-09-07 with the lake's own parser at the pin
  # (`node apps/uplink/bin/uplink.mjs --rows <store path> --parse-only` → rc 0):
  # nine rows — cc, cc2, cc3, codex, pi-qwencloud, cerebras (owner tom /
  # third-party, the seat rows U-D12's feeders write) and gpu-coordinator,
  # gpu-worker, mechanical (owner kernel, window none, context_window 32768 on
  # the two device rows). The uplink probes all nine over the socket; the served
  # kernel answers from its own three rows and the meters dir for the rest, and
  # a probe that fails is written busy with grade UNKNOWN, never as false idle.
  rowsFile = "${inputs.tally-b}/docs/rows.md";

  # The lake's origin: the Worker U-A21/U-A22 deployed on Tom's own account
  # under the name D-B13 fixed (`tally-lake`), banked by the lake repo at
  # receipts/LAKE-DEPLOY/url.txt and printed in its docs/deploy.md. A URL is not
  # a credential — it is inert without the bearer, which is exactly why the
  # Worker refuses every request, reads included, whose Authorization is not
  # `Bearer $LAKE_TOKEN` (lake DECISIONS.md D-A22-1).
  lakeOrigin = "https://tally-lake.thomasmecattaf.workers.dev";

  # The interpreter. The lake's flake records a node store path
  # (nodejs-slim-24.19.0) and cannot do better from inside a pure flake with no
  # inputs — `builtins.storePath` is refused in pure mode, so its pin is a
  # run-time reference and not a build-time one. THIS flake has a pkgs, so it
  # passes a real derivation, which is the seam the lake flake exported for
  # exactly this unit ("`mkUplink` below takes `node` as an argument precisely
  # so U-D14, which HAS a `pkgs`, can pass a real node derivation"): the
  # interpreter is then a closure edge of the generation that installs the unit,
  # GC-protected, instead of a naked store path nothing owns.
  #
  # nodejs-slim_24 (24.18.0 at this nixpkgs pin) rather than nodejs_24: the
  # slim package is `node` and nothing else, which is the same shape the lake
  # records, and the uplink is dependency-free ES modules on node 24 — no npm,
  # no build step, no dependency added (the lake's own law, and this unit's).
  # A version apart from the lake's recorded 24.19.0, deliberately: the pin
  # belongs to whoever installs the unit, and both are node 24.
  #
  # MEASURED: `require('tls').rootCertificates.length` is 120 on BOTH the
  # recorded interpreter and this one, so the unit needs no SSL_CERT_FILE the
  # way home/seat-feeder.nix's python feeders do — node carries its own trust
  # store, and the lake's POSTs are TLS to a workers.dev host.
  node = pkgs.nodejs-slim_24;
in
# The two invariants this unit is graded on, at eval time and on every host that
# imports the module (the import is unconditional; only the enablement is
# gated), so a merge resolution that repoints either one cannot stay green.
assert lib.hasInfix "tally-rewrite" stateSuffix;
assert !(lib.hasInfix "/.local/state/tally/" rowsFile);
assert uplinkPeriod != "";
{
  imports = [
    inputs.tally-lake.homeManagerModules.tally-uplink
  ];

  services.tally-uplink = lib.mkIf isCoordinator {
    enable = true;

    rows = rowsFile;
    lake = lakeOrigin;
    tokenFile = "${rewriteState}/lake-token";

    # The three the lake module already defaults to the same paths, spelled out
    # for the reason above: the unit says what it runs against. `socket` is the
    # served kernel's (U-D13 declared it as <state>/kernel.sock, which is
    # tally-socket's own default_socket_path); `ledger` is the box's gapless
    # chain, read for the replay from last_seq + 1 that closes any gap the lake
    # recorded; `stateDir` is the uplink's own outbox and event log.
    socket = "${rewriteState}/kernel.sock";
    ledger = "${rewriteState}/ledger.jsonl";
    stateDir = "${rewriteState}/uplink";

    # This box's id in the lake's naming: ONE executor per box, and the box that
    # runs an uplink is the box that serves the kernel (spec §2.4 Q2). The worker
    # twin is a ROW that kernel serves, not a second uplink — so this module is
    # enabled on the coordinator and nowhere else, asserted both ways by the
    # `tally-uplink-topology` check in flake.nix.
    executor = "coordinator";

    node = "${node}";

    # The packaged launcher, built through the seam the lake flake exported, so
    # the thing a human runs by hand and the thing the service runs are the same
    # interpreter. The service itself invokes node against the store copy of
    # apps/uplink directly (the lake module's own choice: the sandbox its
    # package builds in has no chmod, so its output is a launcher FILE and not
    # an executable one).
    package = inputs.tally-lake.lib.mkUplink { node = "${node}"; };

    # One wake per invocation: probe, pull, execute what the door admitted,
    # mirror, re-arm, exit. There is still no interval to set HERE — the only
    # instant the uplink itself waits for is a `next_wake_at` the lake handed
    # back — and the value stays 1 now that the timer below owns the cadence:
    # the manager wakes the oneshot, the oneshot does one pass and exits. This
    # is asserted, together with the timer, by flake.nix's
    # `tally-uplink-topology`, so raising it here would be red.
    wakes = 1;

    # `kit` and `plan` stay at their null defaults, and null is the honest
    # state, not an oversight. The kit is the box's argv table (`argv_ref →
    # {argv, cwd, env_allowlist, usage_source}`) and NO kit names an argv for
    # this estate yet: TL-18 is the open Tom line on the Claude-seat one ("no
    # kit names a Claude argv today"), and the uplink never falls back to a
    # command of its own — a proposal carrying an `argv_ref` it cannot resolve
    # is a legible throw, not a guess (DEFERRED.md DF-U-D14-3). The plan body is
    # the acceptor's, re-POSTed to arm and re-arm; authoring one here would be
    # the lake proposing from the wrong side of the seam.
  };

  # The uplink's own subdirectory, declared the way home/seat-feeder.nix declares
  # the rewrite's meters dir and home/tally.nix declares the live one
  # (dotfiles#292): a missing directory should be a legible failure, never a
  # silent no-op. The uplink also creates it recursively itself
  # (apps/uplink/src/queue.mjs:47, src/uplink.mjs:64), so what this rule adds is
  # the MODE — 0700, as for a per-user state subtree of an already private
  # ~/.local/state — and its existence before the first run. Idempotent with
  # seat-feeder's `d %h/.local/state/tally-rewrite 0700` rule over the parent:
  # systemd-tmpfiles `d` lines are, and both say 0700 tom.
  #
  # NO rule for the token FILE, deliberately: creating it empty would be a stub
  # standing in for a credential, and an empty bearer is a 401 that reads like a
  # lake outage. The file is Tom's act (DF-U-D14-2); until it exists the unit
  # fails with "cannot read the lake token file <path>", which names the path.
  systemd.user.tmpfiles.rules = lib.mkIf isCoordinator [
    "d ${rewriteState}/uplink 0700 - - -"
  ];

  # THE WAKE (FIX-E12, dotfiles#351, D-E24). A clock and nothing else: it holds
  # no path, no argv, no credential and no policy — every one of those is the
  # service's above, rendered by the lake's own module — and it exists on the
  # coordinator only, for the same reason the service does (one uplink per box
  # that serves a kernel, spec §2.4 Q2; the worker twin is a ROW that kernel
  # serves). Both halves of that are asserted by `tally-uplink-topology`.
  systemd.user.timers.tally-uplink = lib.mkIf isCoordinator {
    Unit = {
      Description = "tally lake uplink wake (one pass, ${uplinkPeriod} after the previous pass ENDS — FIX-E12, dotfiles#351)";
      # X- keys are systemd's own extension space: ignored by the manager, read
      # by the topology check and by a human running `systemctl --user cat`, so
      # the timer says which cadence it means and where the number came from.
      X-TallyWakePeriod = uplinkPeriod;
      X-TallyWakeForm = "OnUnitInactiveSec";
    };
    Timer = {
      # The first wake after the timer is ARMED (a switch, not a boot), then one
      # period after each pass ENDS — failures included, which is the property
      # that keeps wakes from piling up behind a red run. See the header.
      OnActiveSec = uplinkPeriod;
      OnUnitInactiveSec = uplinkPeriod;
      # No wall-clock backlog, and no catch-up burst at switch time.
      Persistent = false;
      AccuracySec = "${toString timerAccuracySeconds}s";
      Unit = "tally-uplink.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
