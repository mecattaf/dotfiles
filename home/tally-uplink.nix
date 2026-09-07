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
# NOT A SWITCH, AND NOT A CLOCK. This module declares the unit; only U-D19's
# coordinator switch installs it (DEFERRED.md DF-U-D14-1), and nothing here
# starts it on a timer. The uplink holds no schedule of its own — the lake's
# module says so ("the uplink sleeps only until the next_wake_at the lake handed
# it back") and its card's non-goal is "no scheduling logic in the uplink (the
# lake proposes, the door answers)". What starts a run is a socket event, a
# verdict, or a timer somebody else owns: U-D18's filler-lane timer
# (DEFERRED.md DF-U-D14-4). So the unit below is declared with no `Install`
# section — exactly what the upstream module renders — and `wakes = 1`: one wake
# per invocation, never a loop this file authorises.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

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
{
  imports = [
    inputs.tally-lake.homeManagerModules.tally-uplink
  ];

  # THE ONE THING THIS FILE ADDS TO THE LAKE'S RENDERED UNIT, and why it is
  # here rather than upstream (U-D19, dotfiles#322). The lake's module renders a
  # `Type = "oneshot"` service and nothing else; `wakes = 1` means one wake per
  # invocation, so the process probes, pulls, executes, mirrors, re-arms and
  # EXITS. Without `RemainAfterExit`, systemd erases the outcome of that wake
  # the instant it ends: a successful wake and a wake that never happened both
  # read `inactive`, and only a failure is legible. U-D19's card grades the
  # switch on `systemctl is-active tally-kernel.service tally-uplink.service ->
  # active active`, which under the bare oneshot is unreachable BY
  # CONSTRUCTION — not "not yet true", but never true for longer than the
  # milliseconds of one wake.
  #
  # So the unit is given systemd's own idiom for a job whose result outlives
  # its process: after a successful wake the unit stays `active` and MEANS "the
  # last wake of this box's uplink succeeded"; after a failed one it is
  # `failed` and names the error. That is strictly more information than the
  # bare oneshot, and it is what makes the card's clause a measurement rather
  # than a race.
  #
  # WHAT THIS IS NOT, and DF-U-D14-4 is untouched by it: `RemainAfterExit` is
  # not a schedule. It adds no timer, no `Install` section and no `WantedBy` —
  # nothing here fires the unit, exactly as U-D14 deferred, and `flake.nix`'s
  # `tally-uplink-topology` keeps asserting `!(unit ? Install)` beside the new
  # assertion on this key. The first wake is taken by U-D19's post-switch probe
  # (`tools/u-d19-switch-oracle.sh`, clause D); every later wake is whatever
  # spec §2.2b's wake mechanism becomes.
  systemd.user.services.tally-uplink = lib.mkIf isCoordinator {
    Service.RemainAfterExit = true;
  };

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
    # mirror, re-arm, exit. There is no interval here to set — the only instant
    # the uplink waits for is a `next_wake_at` the lake handed back — and no
    # timer in this file (DEFERRED.md DF-U-D14-4).
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
}
