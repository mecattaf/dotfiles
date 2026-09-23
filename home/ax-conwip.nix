{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# ax-conwip — the CONWIP scheduler as ONE long-running user service, declared
# and OFF.
#
# UNIT: none yet; this is a skeleton, not a lane. ISSUE: dotfiles#455 is the
# gate's own bug (nix flake check never reaches `checks`), filed alongside this
# file; the module itself carries no issue of its own and rides PR #454.
# DATE: 2026-09-23. DOC: docs/ax-conwip.md.
#
# WHAT IT IS. `/home/tom/mecattaf/ax-conwip` is a CONWIP scheduler: it reads
# Claude ultracode workflow run records, derives one work item per agent entry,
# admits items under a fixed work-in-progress cap, dispatches each admitted item
# to an ax server as a Task over gRPC (`UpdateTask`, an upsert — ax v0.3.0 has
# no `CreateTask`), and gives the slot back when the Task reaches a phase the
# CONWIP calls terminal, which is `{Completed, Failed, Terminating}` and NOT
# ax's own `{Running, Completed, Failed}`. The output is an append-only ledger.
# Read that repository's DESIGN.md before touching anything here.
#
# WHY THIS FILE EXISTS. So the shape of running it is declared and reviewable
# BEFORE anything runs it, and so the argument list is data in this repository
# rather than a command line somebody types. Every number a running scheduler
# would obey — the cap, the server it dispatches to, the meters it reads — is an
# option below, set in one place, visible in one diff.
#
# THE SEAT METERS ARE AN INPUT AND ONLY AN INPUT. `metersDir` defaults to the
# REWRITE's meters directory, %h/.local/state/tally-rewrite/meters, the one
# home/seat-feeder.nix declares and its three timers write. Not
# ~/.local/state/tally/meters, which is branch (a)'s and is pinned by
# SHA256SUMS; the two estates never share a path. This module never writes into
# either: it declares no tmpfiles rule over the meters directory, it does not
# create it, and the scheduler opens those files read-only. seat-feeder owns
# that directory's existence and its mode, and R44 puts that file out of reach.
#
# FOUR THINGS THIS FILE DELIBERATELY DOES NOT DO.
#
#   1. NO FLAKE INPUT. `/home/tom/mecattaf/ax-conwip` is a local git repository
#      with NO remote (MEASURED 2026-09-23: `git remote -v` is empty). There is
#      nothing for `inputs.ax-conwip` to point at, and a `builtins.fetchGit` of
#      a path on one box is not a declaration — it is a machine-local accident
#      that would break every other host's eval. So the module names a
#      DIRECTORY, `sourceDir`, and says out loud that it is a directory.
#   2. NO PACKAGE. There is no `pkgs/ax-conwip.nix` and no `.#ax-conwip`,
#      because packaging follows the input, and there is no input. The unit
#      below runs the checkout in place, through `pnpm exec tsx`, against the
#      `node_modules` that checkout already carries. That is honest about what
#      it is: a development shape, not a delivered one. It is the single
#      biggest reason `enable` must stay false.
#   3. NO TIMER, and as of 2026-09-23 that is a statement about the PROGRAM and
#      not only about this module. `ExecStart` runs `src/serve.ts`, which polls
#      the records directory on its own interval and holds each admitted slot on
#      a `WatchTask` stream until the CONWIP's release rule gives it back, so the
#      cap holds for the life of the process. There is nothing for a timer to
#      wake, and restarting on a cadence would re-derive and re-admit. Until this
#      date the unit ran `src/cli.ts`, which reads the directory once and exits:
#      a `Type = oneshot` in everything but name, and the mismatch this change
#      closes. Compare home/seat-feeder.nix, which is all timers and no
#      long-running anything, because its job is freshness.
#   4. NOTHING ENABLED, AND NOTHING ARMED EITHER. `enable` defaults to false and
#      is set nowhere, so this module defines NO unit on any host today; the
#      flake check `ax-conwip-topology` asserts exactly that. And even with the
#      gate flipped the unit carries NO `Install` section, so it is declared and
#      not wanted by anything: `systemctl --user start ax-conwip` is a second,
#      separate, deliberate act. Both flips are Tom's. docs/ax-conwip.md carries
#      the runbook.
#
# ONE OPTION BEYOND THE SIX THE BRIEF NAMED, said plainly: `recordsDir`. The
# scheduler's entry point refuses to start without `--records <dir>`
# (src/serve.ts prints usage and exits 2), so a skeleton without it could not
# form a command line at all, and a skeleton that cannot form a command line is
# not a skeleton, it is a comment. Its default is deliberately a path that does
# not exist, and `src/serve.ts` exits 2 on a records directory that is absent
# rather than polling it forever, so an accidental enable produces a legible
# failure and not a silent pass over nothing.
#
# NO SEVENTH OPTION WAS ADDED. `src/serve.ts` also takes `--poll-interval-ms`,
# `--max-ticks`, `--staleness-bound-seconds` and `--live`, and this module
# passes none of them: every one has a conservative default in the program, and
# an option is a thing Tom has to review. `--live` in particular is not passed
# and must never grow a way to be. Dispatch is dry run by default, and the live
# path needs all three of `--live`, `AX_CONWIP_LIVE_HALOGEN=1` and a seat on the
# `["halogen"]` allow list in the program's own `src/seats.ts`.
let
  cfg = config.myAxConwip;

  # A user unit inherits no interactive PATH and no profile. `node`, `pnpm` and
  # `npm` are absent from PATH on both hosts anyway (MEASURED 2026-09-22), so
  # naming the store paths here is not belt-and-braces, it is the only way the
  # unit could ever run.
  runtimePath = lib.makeBinPath [
    pkgs.nodejs_22
    pkgs.pnpm
    pkgs.coreutils
  ];
in
{
  options.myAxConwip = {
    enable = lib.mkEnableOption ''
      the ax CONWIP scheduler as a user service. OFF, and set nowhere. Read
      docs/ax-conwip.md before flipping this: the program is not packaged and
      the unit runs a checkout in place
    '';

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8080";
      example = "127.0.0.1:8099";
      description = ''
        The ax server the scheduler dispatches Tasks to, as `host:port`. This
        is the program's own `--addr`, which is a gRPC target and NOT a URL:
        the transport is plain h2c with insecure credentials, so there is no
        scheme to write. The default is the LOOPBACK address the mock stack
        listens on by default (`ax-mockstack -addr 127.0.0.1:8080`), chosen so
        that an accidental enable on a box with no mock stack running reaches
        nothing at all, and on a box with one running reaches only the mock.
        No default here points at a live host, and none ever should.
        On the coordinator the live ax-server proxy listens on
        myAxFleet.apiListen (127.0.0.1:8099), never on this default
        (ax-fleet-topology asserts they differ).
      '';
    };

    metersDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.home.homeDirectory}/.local/state/tally-rewrite/meters";
      description = ''
        The seat meter directory, read-only, the rewrite's and not branch
        (a)'s. home/seat-feeder.nix declares it and its timers write it; this
        module only reads it and declares no tmpfiles rule over it.

        It is passed BOTH as `AX_CONWIP_METERS` below and as the program's
        `--meters` flag. Until 2026-09-23 only the environment variable was
        set and nothing read it: `src/cli.ts` took no `--meters` and read no
        variable. `src/serve.ts` reads `<metersDir>/<the seat's row>.json`
        once per tick and lets the pure refusal rule decide admission, and a
        refusal costs throughput and never a slot. The scheduler opens those
        files read-only and its ledger writer refuses any path under this
        directory outright.
      '';
    };

    wipCap = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        The work-in-progress cap: how many Tasks may be admitted at once. The
        cap is data and is never derived by the scheduler. One, deliberately,
        which is stricter than the program's own default of 2 and stricter
        than the seat dry run's 3: a cap is the one number where the
        conservative default costs only throughput, and the expensive
        direction is the other one.
      '';
    };

    sourceDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/tom/mecattaf/ax-conwip";
      description = ''
        Where the CONWIP program lives, as a DIRECTORY on this box, because it
        is not packaged and there is no flake input to package it from: the
        repository has no remote. The unit runs `pnpm exec tsx src/serve.ts`
        with this as its working directory, against the `node_modules` that
        checkout already carries. Nothing in the Nix store is built from it
        and nothing here pretends otherwise.
      '';
    };

    recordsDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.home.homeDirectory}/.local/state/ax-conwip/records";
      description = ''
        The directory of `wf_*.json` ultracode run records the scheduler
        derives work items from, and then WATCHES: `src/serve.ts` re-lists it
        every poll interval and derives each new file exactly once, keyed by
        absolute path. `src/serve.ts` exits 2 without this flag, and exits 2
        again if the directory does not exist, so the default below — a path
        that does not exist today — makes an accidental enable fail legibly
        instead of passing silently over nothing.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.home.homeDirectory}/.local/state/ax-conwip";
      description = ''
        This module's own state root, under %h/.local/state/. Nothing is
        written here yet: `src/serve.ts` puts its jsonl ledgers under the
        checkout's own gitignored `out/ledger/`, so run output never becomes
        source. The directory is declared because the ledger belongs here once
        the program is packaged, and because a missing directory turns a first
        run into a silent no-op rather than a legible failure (the same
        reasoning as dotfiles#292).
      '';
    };
  };

  # Gate OFF: mkIf false removes the attribute outright, so with `enable`
  # unset this module contributes NO `systemd.user.services.ax-conwip` key at
  # all, on any host. That is what `checks.ax-conwip-topology` asserts, and it
  # is why adding this file to home/home.nix's imports changes no rendered
  # byte on any host today.
  config = lib.mkIf cfg.enable {
    systemd.user.services.ax-conwip = {
      Unit = {
        Description = "ax CONWIP scheduler: admit ultracode work items under a fixed WIP cap";
        # Read back by `nix eval` the way home/seat-feeder.nix's X-Tally* keys
        # are, so the declared cap and target cannot drift from whatever a
        # future oracle reads. X- is systemd's extension space; the manager
        # ignores these.
        X-AxConwipCap = toString cfg.wipCap;
        X-AxConwipServer = cfg.serverUrl;
        X-AxConwipHost = osConfig.networking.hostName;
      };

      Service = {
        # Long-running, not a oneshot, and `src/serve.ts` is the program that
        # makes that true: it polls the records directory, admits under a cap
        # that holds for the LIFE OF THE PROCESS, and gives a slot back only
        # when the release rule says so. Restarting it silently would re-derive
        # and re-admit. If it dies, that is a fact to read in the journal, not
        # a thing to paper over. It exits 0 on SIGTERM, so a deliberate stop is
        # not reported as a signal death.
        Type = "simple";
        Restart = "no";
        Nice = 10;
        WorkingDirectory = cfg.sourceDir;
        Environment = [
          "PATH=${runtimePath}"
          "AX_CONWIP_STATE=${cfg.stateDir}"
          "AX_CONWIP_METERS=${cfg.metersDir}"
        ];
        # The whole argument list, as data. Every value is an option above.
        # Every flag here is one the program prints under `--print-flags`, and
        # `checks.ax-conwip-topology` asserts the entry point and `--meters`.
        # `--live` is absent and must stay absent.
        ExecStart = lib.escapeShellArgs [
          "${pkgs.pnpm}/bin/pnpm"
          "exec"
          "tsx"
          "src/serve.ts"
          "--records"
          "${cfg.recordsDir}"
          "--addr"
          "${cfg.serverUrl}"
          "--cap"
          "${toString cfg.wipCap}"
          "--meters"
          "${cfg.metersDir}"
        ];
      };

      # NO Install section, deliberately. See point 4 of the header: flipping
      # the gate declares this unit; starting it is a separate act.
    };

    systemd.user.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 - - -"
    ];
  };
}
