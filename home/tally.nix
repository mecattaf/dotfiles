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

  # Fixed receiver used by the coordinator's hardware tripwire. The sleep holds
  # the logical coordinator-gpu gate for 30 minutes.
  # Interrupt priority makes it next, while hardPreempt=false means it never kills
  # the current GPU holder.
  cooldownReceiver = pkgs.writeShellApplication {
    name = "tally-gpu-cooldown";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      temp_c="''${1:?usage: tally-gpu-cooldown <temp_c> <sensor_kind> <threshold_c> <seconds>}"
      sensor_kind="''${2:?}"
      threshold="''${3:?}"
      seconds="''${4:?}"

      [[ "$temp_c" =~ ^[0-9]+$ ]]
      [[ "$threshold" =~ ^[0-9]+$ ]]
      [[ "$seconds" =~ ^[1-9][0-9]*$ ]]
      [[ "$sensor_kind" =~ ^[A-Za-z0-9:_-]+$ ]]

      stamp="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
      dedup="gpu-cooldown-coordinator-''${sensor_kind}-''${temp_c}C-''${stamp}"
      socket="/run/user/$(id -u)/tally/tally.sock"

      exec ${tallyPackage}/bin/tally --socket "$socket" enqueue \
        --source calendar \
        --pool coordinator-gpu \
        --priority interrupt \
        --dedup-key "$dedup" \
        --no-enqueue \
        --evidence exit:0 \
        -- ${pkgs.coreutils}/bin/sleep "$seconds"
    '';
  };

  # Receiver for the crm-build gh producer: one accepted "@tally build"
  # mention on a mecattaf/crm build issue becomes one crm-issue flow run.
  # The wrapper is the enqueued job; the flow's nodes are its children
  # (noEnqueue = false on the producer is what authorizes them).
  crmIssueDispatch = pkgs.writeShellApplication {
    name = "crm-issue-dispatch";
    text = ''
      issue="''${1:?usage: crm-issue-dispatch <issue-number>}"
      [[ "$issue" =~ ^[1-9][0-9]*$ ]]
      exec ${tallyPackage}/bin/tally flow run ${../flows/crm-issue.js} \
        --args "{\"issue\":$issue}"
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
    cooldownReceiver
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
    # plus 6 fixed (fetch, assemble, chunk, embed, index, receipt). Its
    # argsSchema admits 1,500 pages = 9,006 nodes, which is what its
    # meta.maxNodes 10000 declares, so the host must admit that much or the
    # drain dies on long papers at 2am. The NAS corpus of record currently
    # tops out at 1,215 pages (7,296 nodes) with 231 papers above the 282
    # pages a 1,700 cap would have allowed.
    enqueue.fanoutCap = 10000;

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
      # Serializes the crm build campaign: the dispatch wrapper holds this
      # lane for a whole per-issue flow run, so a second accepted mention
      # queues instead of interleaving. Deliberately NOT flow-build — the
      # wrapper's own gate nodes lease that lane and a shared mutex would
      # self-deadlock.
      crm-campaign = {
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

      # The crm build campaign's at-mention intake: an explicit "@tally build"
      # comment by the operator on an open, build-labeled mecattaf/crm issue
      # dispatches one crm-issue flow run for that issue number. Receipts,
      # evidence, and the gate summary go back onto the issue; closing the
      # issue and merging the PR stay with the orchestrator.
      #
      # SUPERSEDED SHAPE — kept deployed, not current practice. tally.nix#235
      # (merged 2026-07-31, aa5c152) makes campaigns a module surface:
      # services.tally.campaigns.<name> renders the flow, the scoped gh
      # producer, the mutex pool, and the receipt/evidence effects from one
      # attrset. This block plus crmIssueDispatch, the crm-campaign pool, and
      # flows/crm-{issue,campaign}.js are the hand-authored prototype that
      # motivated it. Do not copy them for a new campaign; declare a campaign
      # instead. Migrating crm needs one prerequisite the prototype never had:
      # specs/001-crm/tasks.json in mecattaf/crm — a versioned JSON worklist of
      # per-task briefs, which the module witnesses in place of GitHub issues
      # (tasks.md is the current artifact). Rationale and the role split:
      # JULY31-LEARNINGS.md in tally.nix.
      crm-build = {
        kind = "gh";
        enable = true;
        sources = [
          {
            search = {
              repo = "mecattaf/crm";
              labels = [ "build" ];
              state = "open";
              kinds = [ "issue" ];
            };
          }
        ];
        triggers.mentions = [ "@tally build" ];
        # The operator's own account posts the trigger comments.
        allowSelfTriggered = true;
        pollIntervalSec = 60;
        postReceipt = true;
        postEvidence = true;
        # Gate proof lives in the flow's witnessed go build/vet/test nodes and
        # the PR; postGateSummary would require a gateManifest on this wrapper
        # job, which has none.
        postGateSummary = false;
        enqueue = {
          argv = [
            "${crmIssueDispatch}/bin/crm-issue-dispatch"
            "\${gh.number}"
          ];
          pool = "crm-campaign";
          priority = "medium";
          evidence = [ "exit:0" ];
          runtimeMaxSec = 21600;
          noEnqueue = false;
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
}
