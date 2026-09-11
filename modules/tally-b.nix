{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# tally-b — the REWRITE kernel (github.com/mecattaf/tally, U-B1…U-B13) as one
# system service on the coordinator, beside the live daemon and touching none
# of its state.
#
# WHAT RUNS. The flake input `tally-b` is the cargo workspace itself
# (`flake = false` — the repo ships no flake of its own, CONTRIBUTING §1 rule
# 2 in that repo: "This repository carries no Nix at all"). The packaging is
# therefore here and nowhere else: `rustPlatform.buildRustPackage` over
# crates/tally-socket, whose binary IS `tally-kernel` (serve/call/chain/guard).
# The workspace is std-only — its Cargo.lock carries path members and not one
# external crate — so the build needs no cargoHash and no vendoring, and the
# pinned lockfile alone is the supply chain.
#
# COEXISTENCE, as bytes. The live estate is `tally-daemon.service` on tom's
# USER bus (the `tally` input's homeManagerModules, home/tally.nix) writing
# ~/.local/state/tally/. This unit is `tally-kernel.service` on the SYSTEM bus
# writing ~/.local/state/tally-rewrite/ — a different bus, a different unit
# name, a different state root, and the separation is not this module's
# opinion: the kernel's own `Ledger::open` refuses branch (a)'s paths by name
# (tally crates/tally-kernel/src/ledger.rs:31-35), so a served kernel pointed
# at the live state root fails to start. Nothing here reads or writes
# ~/.local/state/tally/, and the live daemon's declaration is untouched.
#
# THE PATHS, each one the kernel's own default made explicit (spec §2.1):
#   state   ~/.local/state/tally-rewrite/            (lib.rs default_state_dir)
#   socket  ~/.local/state/tally-rewrite/kernel.sock (tally-socket
#             default_socket_path: SOCKET_BASENAME beside the chain it fronts)
#   meters  ~/.local/state/tally-rewrite/meters/     (config.rs
#             METERS_BASENAME under the state dir: the kernel-written rows,
#             which U-D12's seat feeders already feed from the user bus)
# serve takes all three by flag; spelling them here means the unit says what
# it runs against instead of inheriting it from $HOME.
#
# NOT A SWITCH. This module declares the unit; only U-D19's coordinator switch
# installs it (DEFERRED.md DF-U-D13-1). Until then `systemctl status
# tally-kernel` on the box answers "could not be found", and that is the
# intended state of a declared-but-not-switched unit — never a hand-started
# one (Rule 9).
let
  cfg = config.services.tally-kernel;

  # The rows the served kernel OWNS — the three `owner: kernel` rows of the
  # rewrite's own docs/rows.md, and nothing else. The seat rows (cc, cc2,
  # cc3, codex, pi-qwencloud) are tom-owned observations written into the
  # meters dir by U-D12's feeders on the user bus; they are read through the
  # meters dir, never served from this file. Every number below is that
  # table's own: capacity 1 per device, `window: none` (a device is contended,
  # never spent), context_window 32768 on the GPU rows and none on
  # `mechanical`, graces 30/10, and the per-attempt cap 100000 that D-B3/TL-3
  # set on every row. One kernel serves both devices because the daemon is one
  # kernel on the coordinator (spec §2.4 Q2) — the worker box runs no kernel
  # of its own. Neither GPU row carries a `running` probe: the coordinator
  # serves no model, and the worker's GPU is held for the life of the Halogen
  # server (modules/halogen.nix), which exposes no "what is loaded" endpoint —
  # so both are `none`, which the kernel records as measured not-applicable
  # rather than as an unknown.
  defaultRows = [
    {
      row = "gpu-coordinator";
      capacity = 1;
      context_window = 32768;
      checkpoint_grace_seconds = 30;
      kill_grace_seconds = 10;
      per_attempt_token_cap = 100000;
      running.kind = "none";
    }
    {
      row = "gpu-worker";
      capacity = 1;
      context_window = 32768;
      checkpoint_grace_seconds = 30;
      kill_grace_seconds = 10;
      per_attempt_token_cap = 100000;
      running.kind = "none";
    }
    {
      row = "mechanical";
      capacity = 1;
      context_window = null;
      checkpoint_grace_seconds = 30;
      kill_grace_seconds = 10;
      per_attempt_token_cap = 100000;
      # The evaluator's row runs no model: nothing to probe, so `none` —
      # which the kernel records as measured false / "not-applicable", not as
      # an unknown.
      running.kind = "none";
    }
  ];

  rowsFile = pkgs.writeText "tally-b-rows.json" (builtins.toJSON cfg.rows);

  package = pkgs.rustPlatform.buildRustPackage {
    pname = "tally-b-kernel";
    version = "0.0.1"; # the workspace's own [workspace.package] version
    src = inputs.tally-b;
    # The pinned Cargo.lock IS the dependency statement: path members only,
    # zero external crates ("A socket is not a reason to acquire a supply
    # chain", tally-socket's own Cargo.toml). importCargoLock over it needs no
    # network and no cargoHash. MEASURED: the built out carries exactly one
    # bin, tally-kernel.
    cargoLock.lockFile = inputs.tally-b + "/Cargo.lock";
    # -p tally-socket: the workspace's other members are the admission CLI and
    # the oracle/fixture binaries; the served kernel is this one package,
    # whose [[bin]] is named tally-kernel (the library package of that name is
    # the kernel it serves — tally-socket's Cargo.toml says why).
    cargoBuildFlags = [
      "-p"
      "tally-socket"
    ];
    doCheck = false; # the workspace's own scripts/test.sh is its oracle (X-A), not this unit's
    meta.mainProgram = "tally-kernel";
  };
in
{
  options.services.tally-kernel = {
    enable = lib.mkEnableOption "tally-kernel.service — the rewrite's served admission kernel (system bus, tally-rewrite state)";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      defaultText = lib.literalExpression "rustPlatform.buildRustPackage over inputs.tally-b (crates/tally-socket)";
      description = "The package carrying the tally-kernel binary (serve/call/chain/guard).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "tom";
      description = ''
        User the served kernel runs as. The state root lives under this user's
        home, the socket is 0600 beside the chain it fronts, and the executor
        this kernel spawns work for runs as this same user.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.local/state/tally-rewrite";
      defaultText = lib.literalExpression ''"/home/''${cfg.user}/.local/state/tally-rewrite"'';
      description = ''
        The rewrite's own state root (ledger.jsonl, kernel.sock, meters/).
        Must carry the tally-rewrite component: the kernel's Ledger::open
        refuses branch (a)'s paths by name, so a stateDir under
        ~/.local/state/tally is a unit that cannot start — asserted below
        rather than discovered at boot.
      '';
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.stateDir}/kernel.sock";
      defaultText = lib.literalExpression ''"''${cfg.stateDir}/kernel.sock"'';
      description = "The AF_UNIX path serve binds — the kernel's own default: SOCKET_BASENAME beside the chain.";
    };

    rows = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = defaultRows;
      description = ''
        The rows this served kernel owns, rendered verbatim to the --rows
        JSON. Shape is tally-socket's config.rs row_from_json: row, capacity,
        context_window (null allowed), checkpoint_grace_seconds,
        kill_grace_seconds, per_attempt_token_cap, running
        ({"kind":"none"} | {"kind":"fixed","value":bool} |
        {"kind":"http","endpoint":url}). Nothing is defaulted server-side — a
        missing cell is refused by name at startup — so this list is the whole
        row policy of the served kernel.
      '';
    };

    evaluatorLock = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to apps/evaluator's pinned lock (EVALUATOR.sha256). Null means no
        verdict is ever derived — the right state until U-A17's evaluator
        exists to be locked (tally docs/socket.md §4).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # The kernel refuses branch (a)'s state root by name; refuse it here
        # too, at eval time, so the failure is a red check and not a boot loop.
        assertion = lib.hasInfix "tally-rewrite" cfg.stateDir;
        message = "services.tally-kernel.stateDir must live under tally-rewrite — the kernel's Ledger::open refuses the live estate's state root (${cfg.stateDir})";
      }
      {
        assertion = cfg.rows != [ ];
        message = "services.tally-kernel.rows is empty; a kernel with no row admits nothing (tally-socket config.rs refuses it at startup)";
      }
    ];

    systemd.services.tally-kernel = {
      description = "tally rewrite kernel — served admission, leases and witness chain over ${cfg.socketPath}";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        ExecStart = lib.concatStringsSep " " (
          [
            "${cfg.package}/bin/tally-kernel"
            "serve"
            "--state ${cfg.stateDir}"
            "--rows ${rowsFile}"
            "--socket ${cfg.socketPath}"
          ]
          ++ lib.optionals (cfg.evaluatorLock != null) [ "--evaluator-lock ${cfg.evaluatorLock}" ]
        );
        Restart = "on-failure";
        RestartSec = 5;
        Umask = "0077";
        # No ProtectHome/ReadWritePaths dance: the whole job of this process
        # is to run admitted work as this user over this user's tree, and its
        # own writes are confined by the state root it refuses to leave
        # (ledger.rs) rather than by a sandbox that would have to exempt the
        # executor's world anyway.
      };
    };

    # The state root and the meters dir, declared the way home/tally.nix
    # declares the live meters dir (dotfiles#292) and home/seat-feeder.nix
    # declares the rewrite's from the user bus: a missing directory should be
    # a legible failure, never a silent no-op. System-side rules with an
    # explicit owner because the creating unit is a SYSTEM service; they
    # coexist with seat-feeder's user-bus rules over the same two paths —
    # systemd-tmpfiles `d` lines are idempotent and both say 0700 tom.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 ${cfg.user} users - -"
      "d ${cfg.stateDir}/meters 0700 ${cfg.user} users - -"
    ];
  };
}
