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
      # crm-campaign is NOT declared here: services.tally.campaigns.crm
      # renders it as the capacity-1 runner mutex, together with the
      # campaign-agent and campaign-control node lanes.
    };

    # The crm build campaign, the first consumer of tally.nix#235. One attrset
    # renders everything the hand-rolled prototype needed six pieces for: the
    # shipped spec-build flow, the scoped gh mention producer, the capacity-1
    # runner mutex, the campaign node lanes, and the driver adapter. The work
    # graph is NOT here and not on GitHub — it is specs/001-crm/tasks.json in
    # mecattaf/crm, witnessed by the flow's first node and projected into one
    # per-task brief. GitHub keeps intake (the labeled campaign issue and its
    # exact mention), steering (comments read at every agent attempt), and
    # projection (receipts, evidence, per-task PRs). Doctrine and the role
    # split: JULY31-LEARNINGS.md in tally.nix.
    campaigns = lib.optionalAttrs isCoordinator {
      crm = {
        enable = true;

        repositories."mecattaf/crm" = {
          checkout = "/home/tom/mecattaf/crm";
          baseBranch = "main";
          remote = "origin";
        };

        # Deliberately NOT "build": issues #1–#19 carry that label and are
        # public anchors for the decomposition, never triggers. Exactly one
        # open issue carries "campaign", and it is the doorbell.
        label = "campaign";
        mention = "@tally build";
        allowedActors = [ "mecattaf" ];

        worklist = "specs/001-crm/tasks.json";
        # The frozen graph is 19 tasks; the cap refuses a worklist that grew.
        maxTasks = 19;

        agent = "codex";

        # The four AGENTS.md gates verbatim, as direct argv. Go is not on
        # PATH; every command goes through nix. The race detector is
        # cgo-backed, hence nixpkgs#gcc in the test gate. These are the merge
        # criterion — witnessed here, not re-reviewed by an agent.
        gates = [
          {
            id = "build";
            argv = [ "nix" "shell" "nixpkgs#go" "-c" "go" "build" "./..." ];
          }
          {
            id = "vet";
            argv = [ "nix" "shell" "nixpkgs#go" "-c" "go" "vet" "./..." ];
          }
          {
            id = "test";
            argv = [ "nix" "shell" "nixpkgs#go" "nixpkgs#gcc" "-c" "go" "test" "-race" "./..." ];
          }
          {
            id = "lint";
            argv = [ "nix" "shell" "nixpkgs#golangci-lint" "-c" "golangci-lint" "run" "./..." ];
          }
        ];

        # Held by the runner for the whole campaign, so a second accepted
        # mention queues instead of interleaving two task chains against the
        # same base.
        pool.name = "crm-campaign";
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
