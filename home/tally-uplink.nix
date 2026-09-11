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

  # ------------------------------------------------------------------ THE KIT
  #
  # TL-18 / D-B18, dotfiles#304. The box's argv table: `argv_ref ->
  # {argv, cwd, env_allowlist, usage_source, stdin}`. The lake never originates
  # an argv (spec §2.2c) and neither does the uplink — a proposal carries the
  # NAME and the BOX carries the command (spec §2.1: "the argv the kit names IS
  # the harness"). This attribute set is that carriage, rendered into the store
  # so the table the unit resolves against is a reviewed artifact and not a file
  # somebody edited on the box (Rule 9, dotfiles#293).
  #
  # A ref with no entry is a refusal that names the ref AND the kit file
  # (`readKit(...).resolve`, lake apps/uplink/src/kit.mjs) — the uplink never
  # falls back to a command of its own, which is why a DISABLED entry below is a
  # stronger statement than an absent one: the refusal says which kit was asked.

  # The one ENABLED job, and it is deliberately LOCAL and deterministic.
  #
  # WHY NOT A CLAUDE SEAT TONIGHT. The first unattended run leases a row the
  # served kernel actually serves — `mechanical` (modules/tally-b.nix serves
  # exactly three: gpu-coordinator, gpu-worker, mechanical). The seat rows (cc,
  # cc2, cc3, codex, pi-qwencloud) are `owner: tom`, written by the U-D12
  # feeders through the meters dir (tally docs/rows.md:41-55,
  # modules/tally-b.nix:57-63 excludes them deliberately); a kernel lease on one
  # of them would make `stamp_row` write `owner: kernel` over a feeder-owned
  # file and give one file two writers. D-B6 already bars unattended spend of
  # the codex seat. Whether the kernel may lease a Claude seat AT ALL, and
  # through which row, is Tom's ruling and is asked in dotfiles#362 — until it
  # lands, nothing here names a seat.
  #
  # WHY NOT THE UTILITY MODEL EITHER, YET. `utility-model` (llama-swap,
  # qwen3.6-35b-a3b on the gpu-coordinator row) is the documented NEXT entry,
  # not tonight's: a cold weight load can outrun a short lease, and the first
  # unattended run should fail for a reason, not for a stopwatch.
  #
  # WHAT IT PROVES. Exactly the seam that has never once been exercised on this
  # box: the kernel resolves `usage_source.path_glob` (first `*` -> the
  # execution id's digest, tally crates/tally-kernel/src/exec.rs:95-140), exports
  # it to the child as TALLY_USAGE_SOURCE_PATH together with TALLY_EXECUTION_ID
  # (exec.rs:689), and writes `usage_source{kind,path}` into the `witness_record`
  # (exec.rs:953-958). The child's whole job is to leave one line at that path
  # carrying the execution id it was given, so the artifact and the receipt name
  # each other. Tonight's receipt is that `witness_record` plus the
  # `lease_release` beside it in ~/.local/state/tally-rewrite/ledger.jsonl.
  #
  # env_clear + an EMPTY env_allowlist is the point (exec.rs:681-687): the child
  # sees the two TALLY_ variables and nothing else, so every path it touches is
  # one the store already names.
  localSmoke = pkgs.writeShellScript "tally-local-smoke" ''
    set -eu
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$TALLY_USAGE_SOURCE_PATH")"
    printf '{"kind":"tally-usage/1","execution_id":"%s","argv_ref":"build:LOCAL-SMOKE","tokens":{"out":0},"ok":true}\n' \
      "$TALLY_EXECUTION_ID" > "$TALLY_USAGE_SOURCE_PATH"
    exit 0
  '';

  # THE HEADLESS CLAUDE SEAT: DESIGNED, DOCUMENTED, AND NOT ENABLED.
  #
  # This attribute is written out in full and then deliberately left OUT of
  # `entries` (`enableClaudeSeat = false` below), so the design is reviewable
  # here rather than reconstructed under time pressure later, and so a proposal
  # naming `claude:headless` is refused by name against a kit file that visibly
  # contains no such entry.
  #
  # WHY IT IS OFF. There is no sanctioned kernel lease on a Claude seat: the
  # seat rows are feeder-owned (tally docs/rows.md:41-55, modules/tally-b.nix:
  # 57-63), D-B6 bars unattended spend of the codex seat, cc3's sign-in is
  # expired and pi-qwencloud is exhausted. `cc` is the seat with headroom, and
  # leasing it is exactly the ruling dotfiles#362 asks Tom for.
  #
  # THE ARGV, AND WHY IT IS NOT D-B18's LITERAL. D-B18's ruled text is
  # `env CLAUDE_CONFIG_DIR=<seat root> claude -p --output-format json
  # --permission-mode bypassPermissions --model opus <brief-file>`. The form
  # below is the CONSERVATIVE default this package states as an ASSUMPTION for
  # Tom to overrule with one comment: `--permission-mode dontAsk` (never
  # prompts, and DENIES what was not pre-allowed) instead of
  # `bypassPermissions` (never prompts, and allows), `--max-turns 20` as a
  # second, cheap bound on a runaway loop, and the brief on the kit's `stdin`
  # rather than as a file path, because the item's brief is the plan's and a
  # path here would be a file this module invented.
  #
  # THE RUNTIME CEILING IS THE LEASE'S (dotfiles#162, "every unattended job has
  # a runtime ceiling that converts a hang into an alert"). It is the envelope's
  # `seconds`, enforced by the kernel's own SIGTERM -> 30 s checkpoint grace ->
  # SIGKILL rail; no second timer is added here, and none should be.
  #
  # THE OPEN HALF OF TL-18 is the `usage_source` wrapper: `claude -p` writes its
  # usage into its own session transcript, not to $TALLY_USAGE_SOURCE_PATH, so
  # enabling this entry means wrapping the binary in a script that copies the
  # session's usage line to the resolved path — the same motion `localSmoke`
  # performs, over a real transcript. Until that wrapper exists this entry would
  # attest a run with no usage record, which is the shape of a receipt that
  # proves nothing.
  claudeSeatEntry = {
    argv = [
      "claude"
      "-p"
      "--output-format"
      "json"
      "--permission-mode"
      "dontAsk"
      "--max-turns"
      "20"
      "--model"
      "opus"
    ];
    # the item's own worktree, handed down by the plan; the placeholder below is
    # not a path this module would ship enabled.
    cwd = "${rewriteState}/uplink/worktree";
    env_allowlist = [
      "HOME"
      "PATH"
      "CLAUDE_CONFIG_DIR"
      "LANG"
      "TERM"
    ];
    usage_source = {
      kind = "claude-code-usage/1";
      path_glob = "${rewriteState}/uplink/usage/claude-*.jsonl";
    };
    # the brief, handed to the child on stdin by exec.run.
    stdin = "";
  };
  enableClaudeSeat = false;

  # The two declared NO-OPs beside the job, under the acceptor's own taskId
  # scheme: a worker ref is the label, its scope and eval cells are
  # `scope(<taskId>)` and `eval(<taskId>)` (the factory proposes `argv_ref ??
  # taskId`). They exist so a whole plan resolves rather than throwing on its
  # second cell.
  #
  # `/bin/sh -c true`, NOT `/bin/true`. MEASURED on this box: /bin holds exactly
  # one entry, `sh`, a symlink into the store; an argv naming /bin/true would
  # attest a spawn failure rather than the pass the cell is about. The lake's own
  # fixture (fixtures/uplink/kit.json) says the same thing.
  noopEntry = kind: glob: {
    argv = [
      "/bin/sh"
      "-c"
      "true"
    ];
    cwd = "/";
    env_allowlist = [ ];
    usage_source = {
      inherit kind;
      path_glob = "${rewriteState}/uplink/usage/${glob}-*.jsonl";
    };
    stdin = "";
  };

  kitFile = pkgs.writeText "tally-uplink-kit.json" (
    builtins.toJSON {
      _note = [
        "The coordinator's KIT (U-D14, TL-18/D-B18, dotfiles#304). argv_ref -> the"
        "command, its cwd, the environment names it may see, where its usage record"
        "lands, and what it is handed on stdin. Generated by home/tally-uplink.nix;"
        "do not edit on the box (Rule 9, dotfiles#293) — edit the module and switch."
        ""
        "ENABLED: build:LOCAL-SMOKE, a deterministic local job for the mechanical row."
        "It writes one JSON line at $TALLY_USAGE_SOURCE_PATH carrying the"
        "$TALLY_EXECUTION_ID the kernel gave it, which is the usage_source join the"
        "witness_record points at."
        ""
        "NOT ENABLED: claude:headless. The seat rows are feeder-owned (tally"
        "docs/rows.md:41-55, modules/tally-b.nix:57-63) and no kernel lease on a"
        "Claude seat is sanctioned; the ruling is asked in dotfiles#362. A proposal"
        "naming it is refused by name against this file, which is the intended"
        "outcome and not a gap."
        ""
        "usage_source.kind is an OPAQUE label the kernel carries and never reads"
        "(tally docs/transport.md §2). It names no harness and nothing branches on it."
      ];
      entries =
        {
          "build:LOCAL-SMOKE" = {
            argv = [ "${localSmoke}" ];
            cwd = "${rewriteState}/uplink";
            env_allowlist = [ ];
            usage_source = {
              kind = "tally-usage/1";
              path_glob = "${rewriteState}/uplink/usage/local-smoke-*.jsonl";
            };
            stdin = "";
          };
          "scope(build:LOCAL-SMOKE)" = noopEntry "opaque-noop/1" "scope-noop";
          "eval(build:LOCAL-SMOKE)" = noopEntry "opaque-noop/1" "eval-noop";
        }
        // lib.optionalAttrs enableClaudeSeat { "claude:headless" = claudeSeatEntry; };
    }
  );
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

    # THE KIT (TL-18 / D-B18, dotfiles#304) — no longer null, and this is the
    # change U-D14 deferred as DF-U-D14-3. The box's argv table now exists as a
    # store file: `argv_ref → {argv, cwd, env_allowlist, usage_source, stdin}`,
    # built above. It names ONE enabled job — `build:LOCAL-SMOKE`, a local
    # deterministic run for the `mechanical` row, whose whole purpose is to
    # close the `usage_source` join the kernel has never yet been given — plus
    # that job's two declared no-op cells, and it deliberately does NOT name the
    # designed `claude:headless` entry: no kernel lease on a Claude seat is
    # sanctioned (D-B6; the ruling is asked in dotfiles#362), and a ref with no
    # entry is a refusal that names the ref and this file rather than a guess.
    #
    # `plan` STAYS NULL, and null is still the honest state for it: the plan
    # body is the acceptor's, re-POSTed to arm and re-arm, and authoring one
    # here would be the lake proposing from the wrong side of the seam. Arming
    # is Tom's act, not this module's.
    kit = "${kitFile}";
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
    # The kit's usage drop. Every `usage_source.path_glob` above resolves under
    # this directory, and the kernel resolves the glob but does NOT create the
    # directory — `localSmoke` mkdir -p's it for the same reason, and this rule
    # gives it the MODE (0700, as for a per-user state subtree) and its
    # existence before the first lease rather than at the mercy of the first
    # child that runs. A usage record is the artifact half of tonight's
    # receipt; a missing directory should be a legible failure, never a silent
    # no-op (dotfiles#292).
    "d ${rewriteState}/uplink/usage 0700 - - -"
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
