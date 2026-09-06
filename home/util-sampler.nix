{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
# util-sampler — the UTIL-01 utilization instrument, as user timers.
#
# CARD (the specification; this file does not restate it):
#   /home/tom/research-methods/cards/UTIL-01.md — its `definition`, `row_schema`
#   and `signal` blocks. ISSUE: dotfiles#311.
#
# WHY THIS EXISTS. Nothing on this estate measures a box-night. The tally lease
# log holds grants and no releases, no serve stamps a receipt with a
# fingerprint, and the only ledger of real GPU work froze on 2026-08-08. A
# declared-on GPU and a working GPU are indistinguishable here. The card's
# answer is a sampler that writes three facts a run cannot fabricate — a lease
# held in the daemon, a serve answering a liveness probe, an evidence event on
# disk — every 60 s, and a row writer that turns a night of those samples into
# one recomputable JSON row per box.
#
# RULE 9 (nothing hand-installed stays so). These two timers are declared here
# BEFORE they have ever run by hand: there is no `~/.config/systemd/user/util-*`
# pair to disable and delete first, and there must never be one. The programs
# themselves are RAW dotfiles reached through the whole-dir ~/.local/bin
# out-of-store symlink (home/home.nix:205), so the units name
# `%h/.local/bin/util-*` and supply their own PATH — a systemd user unit
# inherits none of the interactive session's.
#
# THE PROGRAMS, and their sha256 — the same bytes as kits/util/, verified equal
# at the commit that added them. The card's `abort_on` makes a row written by an
# instrument whose digest differs from the value locked at arming a CRASH, which
# is why the digests are written down here and not only in the kit:
#
#   home/dot_local/bin/util-sampler
#     cc76a8179c46e735d6005f3f2d92f137cff026d7c3658a27b89261778fa50ce6
#   home/dot_local/bin/util-row
#     1fdb80179595dc151af67e4ed2bc03e6a3bcf34685acb869b1cc9d9bcfa90906
#
# WHAT THIS FILE DOES NOT DO. It declares units; it enables nothing by hand,
# starts no serve, holds no GPU, and sends no inference request. The sampler's
# only verb is GET, against health/arms/metrics endpoints. Neither program
# writes anywhere but `~/.local/state/tally/meters/util-*`; the OCR drain's
# ledger is opened read-only and never written.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # The tally binary IS nameable as a package in this flake — home/tally.nix:20
  # resolves it the same way and home/tally.nix:264 runs it by store path. So
  # the coordinator sampler gets the real derivation on PATH rather than the
  # system profile path `/etc/profiles/per-user/tom/bin`, and the unit therefore
  # cannot silently lose `tally query pools` to a profile that was rebuilt.
  tallyPackage = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;

  # python3 stdlib only, both programs; coreutils for the shell-out-free odds
  # and ends a oneshot still expects to find.
  samplerPath = lib.makeBinPath (
    [
      pkgs.python3
      pkgs.coreutils
    ]
    # The WORKER has no tally daemon and no tally binary (measured 2026-09-06),
    # and the sampler is written for that: its pools answer is `null` on the
    # worker, never an empty held map. Putting tally on the worker's PATH would
    # be a lie about what that box can answer, so it is coordinator-only.
    ++ lib.optionals isCoordinator [ tallyPackage ]
  );

  # The row writer additionally pulls the worker's sampler log with
  # `scp -o BatchMode=yes -p` (util-row:322), so it needs openssh. It reads the
  # worker; it never writes there.
  rowPath = lib.makeBinPath [
    pkgs.python3
    pkgs.coreutils
    pkgs.openssh
  ];
in
{
  # ── the sampler, BOTH boxes ────────────────────────────────────────────────
  #
  # NOT coordinator-gated, and that is the whole point: a box-night is measured
  # per box, and the worker is the box holding 94.7 GB of GTT under a serve with
  # no lease. The program decides which box it is by hostname and picks its own
  # probe list and lease pool from the card's `vram_pool_by_box`; no Nix
  # conditional selects them, so the two boxes run one identical program.
  systemd.user.services.util-sampler = {
    Unit.Description = "One utilization sample (UTIL-01)";
    Service = {
      # One sample per invocation. There is no loop in the program — the timer
      # is the clock. A missed run is a gap in the log, which is exactly what
      # the row's max_gap_s is there to report.
      Type = "oneshot";
      # Same reason as the harness records: a meter must never compete with the
      # work it is metering.
      Nice = 10;
      Environment = [
        "PATH=${samplerPath}"
        # %S is XDG_STATE_HOME for a user unit; this is the card's
        # row_schema.sampler_log root, named explicitly rather than left to the
        # program's ~/.local/state default.
        "UTIL_METERS=%S/tally/meters"
      ];
      ExecStart = "%h/.local/bin/util-sampler";
    };
  };

  systemd.user.timers.util-sampler = {
    Unit.Description = "60-second utilization sampling (UTIL-01)";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "60s";
      # The card's T1 reads "no gap > 300 s" off the sampler log. systemd's
      # default 1-minute accuracy would let a 60 s timer drift into buckets of
      # its own; AccuracySec=1s keeps the grid a grid, so that a gap in the log
      # means a box that was down, not a timer that was coalesced.
      AccuracySec = "1s";
      # Deliberately NOT Persistent: a catch-up burst after a boot would write
      # several samples carrying the same instant, and every one of them would
      # be a fabricated reading of a GPU nobody was watching. A box that was off
      # must show as absent samples.
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # ── the row writer, COORDINATOR only ───────────────────────────────────────
  #
  # Coordinator-gated because it is the joiner: it reads BOTH boxes' sampler
  # logs (pulling the worker's read-only over ssh), the coordinator's lease
  # events, the drain ledger and the declared receipt roots, and writes one row
  # per box per night plus the ISO-week rollup. Running it on the worker too
  # would produce a second, poorer row for the same night from a box that can
  # see neither the lease log nor the ledger.
  systemd.user.services.util-row = lib.mkIf isCoordinator {
    Unit.Description = "Write yesterday's utilization row for both boxes (UTIL-01)";
    Service = {
      Type = "oneshot";
      Nice = 10;
      Environment = [
        "PATH=${rowPath}"
        "UTIL_METERS=%S/tally/meters"
      ];
      ExecStart = "%h/.local/bin/util-row";
    };
  };

  systemd.user.timers.util-row = lib.mkIf isCoordinator {
    Unit.Description = "Nightly utilization row (UTIL-01)";
    Timer = {
      # The card's row_schema writes the row at 00:05 over the PREVIOUS local
      # day, so the writer never races a day still being sampled. util-row's
      # --date defaults to yesterday for the same reason.
      OnCalendar = "*-*-* 00:05:00";
      # A box that was asleep at 00:05 still writes that night's row on wake.
      # Unlike the sampler, catching up fabricates nothing: the row is a pure
      # function of a sampler log that is already closed.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # ── the meters subtree, BOTH boxes ─────────────────────────────────────────
  #
  # `~/.local/state/tally/meters/util-sampler/` is the only directory either
  # program creates, and the sampler creates it itself — but a declared
  # directory is the difference between "the first sample of the night is where
  # the card says it is" and "wherever the first invocation happened to be able
  # to write".
  #
  # The PARENT `meters/` is declared in home/tally.nix only on the coordinator
  # (dotfiles#292, on P05's branch). It is deliberately not re-declared here:
  # systemd-tmpfiles creates missing parents for a `d` line, so this one rule
  # gives the worker the whole path, and re-stating the parent would be a
  # duplicate line for the same path in the same generated conf.
  #
  # Mode 0700 is PROPOSED (R-03), matching what home/tally.nix proposes for the
  # parent: a per-user state subtree of an already-private ~/.local/state.
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/tally/meters/util-sampler 0700 - - -"
  ];
}
