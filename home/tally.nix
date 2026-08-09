{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
# tally — the single coordinator for user-decided impure work.
#
# home/home.nix is shared by the fleet, but the daemon, logical pools, local
# executor, and calendar producers exist ONLY on coordinator.
# zenbook-duo remains a best-effort target of the coordinator-owned deploy
# workflow and is not required for coordinator maintenance.
#
# The calendar remains systemd's clock, while tally owns admission, ordering,
# execution, and proof. One nightly item leases the build lane and coordinator GPU
# for the complete local build/deploy transaction, so it waits for active work
# while keeping maintenance local to the coordinator.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  tallyPackage = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;

  systemService = unit: [
    # NixOS installs sudo's setuid entry point in security.wrapperDir. The
    # package symlink under /run/current-system/sw/bin is deliberately not
    # setuid, so it cannot be used by Tally's unprivileged local/SSH executors.
    "${osConfig.security.wrapperDir}/sudo"
    "-n"
    "/run/current-system/sw/bin/systemctl"
    "--wait"
    "start"
    unit
  ];

  # Steward narration shim (wave-3 estate E6, dotfiles#138). The publish node
  # hands a JSON narration request on stdin and reads the proposal back from
  # the one TALLY_FINAL_MESSAGE= line; the proposal is text only —
  # {type, scope, subject, body} — validated by the driver's commitlint-shaped
  # gate, so a malformed answer (or a nonzero exit here) falls back to the
  # brief-derived template and never blocks a merge. Sonnet per the AUGUST-01
  # ruling ("start with Sonnet while the mechanism stabilizes"); credentials
  # are the fleet's seeded Claude OAuth state (modules/secrets.nix), so
  # nothing secret lives here. The narrator is a direct-argv subprocess of the
  # publish node: no launch policy, no hardening, no writable paths — the
  # steward seam refuses adapters that declare them.
  narratorShim = pkgs.writeShellApplication {
    name = "tally-narrator";
    runtimeInputs = [
      pkgs.jq
      pkgs.gnused
      pkgs.coreutils
    ];
    text = ''
      request="$(cat)"
      proposal="$(printf '%s\n' "$request" | /etc/profiles/per-user/tom/bin/claude \
        -p --model sonnet --output-format text \
        "Narrate this campaign publication. The JSON on stdin describes a merged task: derive one conventional commit message from it. Reply with EXACTLY one JSON object, no code fences, no prose: {\"type\": <conventional type>, \"scope\": <short lowercase scope or null>, \"subject\": <imperative, <=60 chars, no leading capital, no trailing period>, \"body\": <plain prose wrapped at 100 columns, under 4000 chars>}. Never include closing keywords (Closes/Fixes #n) or @mentions anywhere.")"
      # Strip accidental fences, then require a single valid object with the
      # four expected fields; jq failing exits the shim nonzero -> template.
      printf 'TALLY_FINAL_MESSAGE=%s\n' "$(
        printf '%s\n' "$proposal" | sed '/^```/d' | jq -c '{type, scope, subject, body}'
      )"
    '';
  };

in
{
  imports = [
    inputs.tally.homeManagerModules.tally
    ../flows/tally-flows.nix
  ];

  home.packages = lib.optionals isCoordinator [
    pkgs.academic-ocr
    pkgs.local-ai-monthly
  ];

  services.tally = {
    enable = isCoordinator;

    # A declaratively deployed flow runner is itself a job, so every node it
    # enqueues is a child bounded by this cap — it is the whole-flow ceiling,
    # not just a build-time check. The retired mutation ladder's 1,700 (100
    # pages × four protocols × four inputs, plus 100 arbiters) died with the
    # Turner/Fosfuri sample flows in e61f906b; academic-paper-e2e replaced it
    # and spends 6 nodes per page (raster, mech, 8B, compare, 32B, compare)
    # plus 6 fixed (fetch, assemble, chunk, embed, index, receipt). The
    # mech-first shortcut (#147, PR #150) added a second mechanical engine and
    # agreement gate per page, so the script's meta.maxNodes rose to 11,000;
    # the host must admit that much or the drain dies on long papers at 2am —
    # the new tally pin refuses the config outright when this cap is below the
    # script meta. The NAS corpus of record currently tops out at 1,215 pages
    # with 231 papers above the 282 pages a 1,700 cap would have allowed.
    enqueue.fanoutCap = 11000;

    # These are real contention lanes, not synthetic maintenance pools.
    pools = lib.optionalAttrs isCoordinator {
      build = {
        resource = "build-slot";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      # "build" is reserved by Tally v0.1.0 for drv() nodes. Shell nodes in
      # these flows use a distinct lane, and the nightly deploy leases both so
      # it remains exclusive with either kind of flow build.
      flow-build = {
        resource = "build-slot";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      coordinator-gpu = {
        resource = "vram";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      academic-ocr-cpu = {
        resource = "cpu-slot";
        capacity = 2;
        enforce = "cooperative";
        hardPreempt = false;
      };
      local-ai-review = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      # Tally v0.1.0 models a capacity-one subscription concurrency lane as a
      # mutex; windowed-consumption budget pools are intentionally unavailable
      # to flow nodes.
      codex-window = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      # The NAS data spindle as a contention lane (#135): the weekly journal
      # archive leases it now; future borg backups and supervised LaCie mirror
      # runs against /mnt/nas must lease it too so bursts never overlap on the
      # same disk.
      nas-hdd = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
    };

    # All jobs execute locally on coordinator; no daemonless SSH executor is
    # part of the active topology.
    executors = { };

    adapters = lib.optionalAttrs isCoordinator {
      ocr-driver = inputs.tally.lib.adapters.mkAdapter {
        argv = [ ];
        scrape.finalMessage = inputs.tally.lib.adapters.mkScrapeCapture {
          pattern = "^TALLY_FINAL_MESSAGE=(.*)$";
        };
      };
      # The steward catalog role (E6): campaigns bind it via `steward =
      # "narrator"`. Which model answers, where, and with which credentials
      # live HERE, never in campaign options — swapping narrators is an
      # adapter change.
      narrator = inputs.tally.lib.adapters.mkAdapter {
        argv = [ (lib.getExe narratorShim) ];
        scrape.finalMessage = inputs.tally.lib.adapters.mkScrapeCapture {
          pattern = "^TALLY_FINAL_MESSAGE=(.*)$";
        };
      };
    };

    # E5 (dotfiles#138): bind code-result revisions to git-ai authorship
    # notes, advisory posture first — an unprovisioned host and a squash that
    # lost its attribution produce identical evidence, so advisory is how the
    # binding proves itself before anything is allowed to fail on it. git-ai
    # 1.6.17 is externally provisioned (verified on the estate 2026-08-03);
    # tally.nix does not ship the binary.
    gitAi = {
      enable = true;
      mode = "advisory";
    };

    # One low-priority durable row replaces the old 02:00/03:30/04:30/06:00 chain.
    # It holds the build and coordinator GPU lanes end-to-end, making the measured
    # single-node build plus activation one exclusive maintenance window.
    # The system service handles Zenbook's successful offline/low-power skip internally.
    producers = lib.optionalAttrs isCoordinator {
      # The parent serializes one monthly review but does not reserve the GPU.
      # After deterministic Git/Nix/HF preparation it enqueues one low-priority
      # coordinator-gpu child for Pi, waits for the commentary, then verifies and
      # publishes without a GPU lease. noEnqueue=false is the deliberate child
      # capability; Tally injects the parent identity and socket for that call.
      monthly-local-ai-review = {
        kind = "calendar";
        onCalendar = "*-*-01 00:30:00";
        enqueue = {
          argv = [
            "${pkgs.local-ai-monthly}/bin/local-ai-monthly-tally"
            "--tally"
            "${tallyPackage}/bin/tally"
          ];
          pool = "local-ai-review";
          priority = "low";
          dedupKey = "monthly-local-ai-review-%Y-%m";
          evidence = [
            "exit:0"
            "artifact:/home/tom/.local/state/local-ai-monthly/last-run.json"
            "hash:sha256"
          ];
          runtimeMaxSec = 43200;
          noEnqueue = false;
        };
      };

      # #135 workstream 1, final piece: one weekly burst moves rotated remote
      # journal files NVMe→HDD on the NAS. The verdict carries the liveness
      # dead-man's switch — the service exits nonzero when no new journal
      # bytes arrived since the previous run, so "uploads quietly stopped"
      # surfaces as a failed tally job instead of silence.
      weekly-journal-archive = {
        kind = "calendar";
        onCalendar = "Sun 03:30";
        enqueue = {
          pool = "nas-hdd";
          argv = systemService "journal-archive.service";
          priority = "low";
          dedupKey = "weekly-journal-archive-%Y-%W";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

      nightly-fleet-deploy = {
        kind = "calendar";
        onCalendar = "02:00";
        enqueue = {
          pool = [
            "build"
            "flow-build"
            "coordinator-gpu"
          ];
          argv = systemService "fleet-deploy.service";
          priority = "low";
          dedupKey = "nightly-fleet-deploy-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };
    };
  };

  # The module's 90s TimeoutStartSec is a per-phase budget, but the unit-facts
  # startup phase probes systemd once per non-terminal durable event row — an
  # O(corpus) cost inside one phase, with no extension until the phase ends. At
  # this host's ~25k-row academic-drain corpus that is ~90-95s, so daemon
  # restarts sit right on the budget and can loop through several timed-out
  # attempts (2026-08-06 pin advance: two 92s failures, then success). Ceiling
  # raised until tally.nix#428 extends the budget inside the loop.
  systemd.user.services.tally-daemon = lib.mkIf isCoordinator {
    Service.TimeoutStartSec = lib.mkForce "10min";
  };

  # sd-switch, which home-manager activation uses to restart changed user
  # units, waits only 120s per job by default — less than the daemon's real
  # ~2m15s time-to-ready on this corpus. The 2026-08-08 nightly deploy failed
  # exactly there: the daemon started clean in 130.9s (#428 renewing the
  # per-phase budget in-loop) while sd-switch had already given up ("timed out
  # waiting on channel"), failing home-manager-tom.service and rolling back an
  # otherwise-good generation. Match the daemon's 10min start ceiling; this is
  # a maximum wait, not a delay.
  systemd.user.servicesStartTimeoutMs = lib.mkIf isCoordinator 600000;
}
