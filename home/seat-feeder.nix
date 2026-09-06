{
  lib,
  osConfig,
  pkgs,
  ...
}:
# tally-seat-feeder — one user timer per external-seat instrument, at half-tick.
#
# UNIT: U-D12 DF-SEAT-FEEDER. ISSUE: dotfiles#315. SPEC: /home/tom/sept7/plan/
# TALLY-SPEC-2026-09-06.md section 2.4 "Freshness and the feeder", section 6.1
# finding C7, section 7 amendment 2. DOC: docs/local-ai/seat-feeder.md.
#
# WHY THIS FILE EXISTS. The rewrite kernel refuses a stale observation: any row
# older than one 60 s tick is SLOW `stale_observation`, and SLOW is a refusal
# (tally crates/tally-kernel/src/admission.rs:126-139, :501-510, :46-48). The
# rows the kernel owns are re-stamped by the kernel at every probe. The external
# seat rows had no writer at all, so every one on this box was stale by
# construction — finding C7, "every seat row stale by construction; no feeder".
# These timers are the writer. Their whole job is freshness; they decide
# nothing.
#
# THE THREE TIMERS, one per instrument, named for what they read:
#
#   tally-seat-feeder-claude        the Claude seats cc, cc2, cc3, through the
#                                   ONE sanctioned credential reader,
#                                   `stamp-receipt.py window` (DECISIONS.md
#                                   D-B5 / TL-5 set: it may read the OAuth file
#                                   and never prints a value). ENABLED — section
#                                   7 amendment 2 lifts section 2.4's "wired but
#                                   not enabled" gating.
#   tally-seat-feeder-codex         the codex row, from the `rate_limits`
#                                   records Codex writes into its own rollouts.
#                                   owner third-party (D-B6): the one Codex
#                                   login on this box is Nayla's
#                                   (RULINGS.md R-2026-09-06-02).
#   tally-seat-feeder-pi-qwencloud  the pi-qwencloud row, grade UNKNOWN with the
#                                   reason named in the row (D-B17 / TL-17
#                                   unset). It exists so the deferral is data.
#
# WHY THREE AND NOT FIVE. The manifest's DOMINANT oracle reads "nix eval of the
# coordinator config shows the THREE timers declared", and its title enumerates
# three instruments over five fed rows. The Claude instrument is one program
# reading one endpoint for three seats that share nothing but a shape, so it is
# one unit that writes three rows — cc and cc2 stay two pools with two reset
# clocks (D-B5), never summed, and cc3 gets its own row on the same tick. See
# DECISIONS.md (U-D12) for the line and its consequence.
#
# RULE 9 (nothing hand-installed stays so). These units are declared here before
# they have ever run by hand; there is no ~/.config/systemd/user/tally-seat-*
# pair to disable and delete first, and there must never be one.
#
# WHAT THIS FILE DOES NOT DO. It switches nothing (U-D19 owns the switch). It
# touches no unit that writes under ~/.local/state/tally/ — branch (a)'s live
# meters directory is pinned by SHA256SUMS, and the feeder program refuses by
# construction to write into it (home/dot_local/bin/tally-seat-feeder,
# `meters_dir`). It runs no argv on a seat and spends nothing: the Claude reader
# is an HTTP GET against the usage endpoint, the Codex reader opens rollout
# files read-only, and the pi writer reads nothing at all.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # The program is a RAW dotfile reached through the whole-dir ~/.local/bin
  # out-of-store symlink (home/home.nix:206), the same motion as
  # home/tally.nix's capacity oracle and home/harness-records.nix's recorders:
  # a threshold or a row field is retuned by editing a file, not by a rebuild.
  # Its delivered sha256 is
  # 8c67fba64c814347f5cd491e062d5a38f670eb9371ec97ee7acfcbcc9c4aa550;
  # the first U-D12 commit records the same digest, following UTIL-01's motion.
  # A systemd user unit inherits no interactive PATH, so each unit supplies its
  # own.
  feeder = "%h/.local/bin/tally-seat-feeder";

  # python3 (stdlib only, both this program and the reader it execs) plus
  # coreutils for the odds and ends a oneshot still expects to find.
  feederPath = lib.makeBinPath [
    pkgs.python3
    pkgs.coreutils
  ];

  # The rewrite's meters directory. NOT ~/.local/state/tally/meters, which is
  # branch (a)'s and pinned; the two estates never share a path.
  metersDir = "%h/.local/state/tally-rewrite/meters";

  # Policy::default().tick_ms = 60_000 and stale_ticks = 1. D-B48 requires a
  # feeder period no greater than HALF that bound: with the declared 1-second
  # timer accuracy, the longest permitted gap is 31 seconds, leaving margin
  # below the kernel's 60-second refusal boundary.
  policyTickSeconds = 60;
  feederPeriodSeconds = 30;
  timerAccuracySeconds = 1;

  instruments = {
    claude = {
      description = "Claude seat rows (cc, cc2, cc3) from the sanctioned usage reader";
      rows = [
        "cc"
        "cc2"
        "cc3"
      ];
      # The reader is research-methods bin/stamp-receipt.py, out of store and
      # out of this repository on purpose: it is the ONE program authorised to
      # open ~/.claude*/.credentials.json (D-B5), and dotfiles neither copies it
      # nor re-implements it. Absent, the feeder still writes each row, with
      # grade UNKNOWN and that absence as the reason.
      environment = [
        "TALLY_STAMP_RECEIPT=%h/research-methods/bin/stamp-receipt.py"
        "TALLY_CLAUDE_SEATS=cc cc2 cc3"
        # A user unit inherits no profile, so the HTTPS trust store is named.
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
      ];
    };
    codex = {
      description = "the codex row from the rollouts' own rate_limits records";
      rows = [ "codex" ];
      # Only ~/.codex/sessions/**/*.jsonl is ever opened. ~/.codex/auth.json is
      # not named here and is never read (D14).
      environment = [ "TALLY_CODEX_SESSIONS=%h/.codex/sessions" ];
    };
    pi-qwencloud = {
      description = "the pi-qwencloud row, grade UNKNOWN with its reason (TL-17)";
      rows = [ "pi-qwencloud" ];
      environment = [ ];
    };
  };

  service = name: spec: {
    Unit = {
      Description = "tally seat feeder: ${spec.description}";
      # Read by tools/feeder-fixture.sh through `nix eval`, so the fixture's
      # row list and the estate's cannot drift apart silently. X- keys are
      # systemd's own extension space and are ignored by the manager.
      X-TallyRows = lib.concatStringsSep "," spec.rows;
      X-TallyTickSeconds = toString policyTickSeconds;
    };
    Service = {
      # One stamp per invocation. There is no loop in the program — the timer
      # is the clock. A missed run is a gap, and the next probe reads it as
      # SLOW stale_observation, which is the honest answer.
      Type = "oneshot";
      # A meter must never compete with the work it is metering (the same
      # reason home/harness-records.nix nices its recorders).
      Nice = 10;
      Environment = [
        "PATH=${feederPath}"
        "TALLY_REWRITE_METERS=${metersDir}"
      ]
      ++ spec.environment;
      ExecStart = "${feeder} ${name}";
      # Retain the delivered 50-second service ceiling: the three sequential
      # Claude readers each have a 12-second internal timeout, and failures
      # become UNKNOWN rows rather than an unbounded service.
      TimeoutStartSec = "${toString (policyTickSeconds - 10)}s";
    };
  };

  timer = name: spec: {
    Unit.Description = "tally seat feeder half-tick (${toString feederPeriodSeconds}s): ${spec.description}";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "${toString feederPeriodSeconds}s";
      # D-B48: AccuracySec is part of the gap, not harmless jitter. At the
      # worst legal expiry the row is 30 + 1 = 31 seconds old, still safely
      # inside the kernel's one-tick (60-second) staleness bound.
      AccuracySec = "${toString timerAccuracySeconds}s";
      Unit = "tally-seat-feeder-${name}.service";
      # This is a monotonic tick, not a wall-clock backlog: no Persistent
      # catch-up is declared.
    };
    # D-B5 / section 7 amendment 2: TL-5 is set, so the Claude feeder is
    # ENABLED like the other two. Nothing here is wired-but-off.
    Install.WantedBy = [ "timers.target" ];
  };

  named = f: lib.mapAttrs' (name: spec: lib.nameValuePair "tally-seat-feeder-${name}" (f name spec));
in
{
  systemd.user.services = lib.mkIf isCoordinator (named service instruments);
  systemd.user.timers = lib.mkIf isCoordinator (named timer instruments);

  # The rewrite's meters directory, created by the module the same way
  # home/tally.nix creates the live one (dotfiles#292, 1ea2f65b): a missing
  # directory would make the first feeder run a silent no-op rather than a
  # legible failure. Mode 0700, as for a per-user state subtree of an already
  # private ~/.local/state.
  systemd.user.tmpfiles.rules = lib.mkIf isCoordinator [
    "d %h/.local/state/tally-rewrite 0700 - - -"
    "d ${metersDir} 0700 - - -"
  ];
}
