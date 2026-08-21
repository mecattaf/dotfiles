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

  # Steward shim (wave-3 estate E6, dotfiles#138; made role-aware at the eta
  # chapter-4 sitting, 2026-08-18). Two delivery channels, one per role: the
  # publish node hands a JSON narration request on STDIN (the narrator is a
  # direct-argv subprocess of the publish node), while a diagnosis dispatch
  # arrives as a daemon job unit whose brief is a FILE named by TALLY_BRIEF —
  # job units have no stdin, which is why the pre-2026-08-18 stdin-only shim
  # answered every diagnosis with the narration schema (result-schema-mismatch
  # on every auto-diagnosis; eta run-log, carried finding at the C2 close).
  # The brief's role field is the discriminator: only the diagnosis brief
  # carries role:"diagnosis" (spec-build.js diagnosisBrief; the narration
  # request has no role key).
  #   - narration: {type, scope, subject, body}, validated by the driver's
  #     commitlint-shaped gate; malformed answer or nonzero exit falls back to
  #     the brief-derived template and never blocks a merge. Sonnet per the
  #     AUGUST-01 ruling ("start with Sonnet while the mechanism stabilizes").
  #   - diagnosis: {verdict, diagnosis[, proposal]} per the flow's
  #     diagnosisResultSchema; the brief's own mission text is the complete
  #     instruction set. Opus (evaluator tier stays off the metered rail, E5
  #     rule 7; operator adapter ruling 2026-08-18). A shape-invalid answer
  #     exits nonzero -> a legible node failure, never a schema-mismatch.
  # Credentials are the fleet's seeded Claude OAuth state (modules/secrets.nix),
  # so nothing secret lives here. No launch policy, no hardening, no writable
  # paths — the steward seam refuses adapters that declare them.
  narratorShim = pkgs.writeShellApplication {
    name = "tally-narrator";
    runtimeInputs = [
      pkgs.jq
      pkgs.gnused
      pkgs.coreutils
    ];
    text = ''
      if [ -n "''${TALLY_BRIEF:-}" ] && [ -r "''${TALLY_BRIEF}" ]; then
        request="$(cat "''${TALLY_BRIEF}")"
      else
        request="$(cat)"
      fi
      role="$(printf '%s\n' "$request" | jq -r '.role // empty' 2>/dev/null || true)"
      if [ "$role" = "diagnosis" ]; then
        answer="$(printf '%s\n' "$request" | /etc/profiles/per-user/tom/bin/claude \
          -p --model opus --output-format text \
          "You are the diagnosis steward for a tally campaign. The JSON on stdin is a diagnosis brief; its mission field is your complete instruction set — execute it against the evidence in the brief's task, failure, gateOutputs, taskBrief, diff, and previousDiagnoses fields. Reply with EXACTLY one JSON object, no code fences, no prose: {\"verdict\": \"retry\"|\"blocked\"|\"transient\", \"diagnosis\": <string per the brief's contract>}, adding \"proposal\" only when verdict is blocked and the brief's contract calls for one.")"
        # Enforce the diagnosis result shape; jq error() exits nonzero -> the
        # node fails legibly instead of answering with the wrong schema.
        printf 'TALLY_FINAL_MESSAGE=%s\n' "$(
          printf '%s\n' "$answer" | sed '/^```/d' | jq -c '
            if ((.verdict=="retry" or .verdict=="blocked" or .verdict=="transient")
                and (.diagnosis|type=="string" and length>0))
            then (if .verdict=="blocked" and has("proposal")
                  then {verdict, diagnosis, proposal}
                  else {verdict, diagnosis} end)
            else error("diagnosis result shape invalid") end'
        )"
      else
        proposal="$(printf '%s\n' "$request" | /etc/profiles/per-user/tom/bin/claude \
          -p --model sonnet --output-format text \
          "Narrate this campaign publication. The JSON on stdin describes a merged task: derive one conventional commit message from it. Reply with EXACTLY one JSON object, no code fences, no prose: {\"type\": <conventional type>, \"scope\": <short lowercase scope or null>, \"subject\": <imperative, <=60 chars, no leading capital, no trailing period>, \"body\": <plain prose wrapped at 100 columns, under 4000 chars>}. Never include closing keywords (Closes/Fixes #n) or @mentions anywhere.")"
        # Strip accidental fences, then require a single valid object with the
        # four expected fields; jq failing exits the shim nonzero -> template.
        printf 'TALLY_FINAL_MESSAGE=%s\n' "$(
          printf '%s\n' "$proposal" | sed '/^```/d' | jq -c '{type, scope, subject, body}'
        )"
      fi
    '';
  };

in
{
  imports = [
    inputs.tally.homeManagerModules.tally
    ../flows/tally-flows.nix
  ];

  home.packages = lib.optionals isCoordinator [
    pkgs.call-diarize
    pkgs.local-ai-monthly
  ];

  services.tally = {
    enable = isCoordinator;

    # The largest registered coordinator flow is errata-map.
    enqueue.fanoutCap = 400;

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
      # nas-hdd mutex REMOVED 2026-08-21 (Tom: "it's fiction"). It claimed to
      # model the NAS data spindle, but once the NAS runs its own overnight
      # builds/GC/backups, most spindle contention is NAS-originated and
      # invisible to a coordinator-side lease. If a real interlock is ever
      # needed it must live on the NAS. What remains below is deliberately
      # narrower: tally requires every enqueue to name a non-empty pool set,
      # and this one arbitrates only COORDINATOR-INITIATED NAS I/O against
      # itself (one weekly job today) — it promises nothing about the disk.
      coordinator-nas-io = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
    };

    # All jobs execute locally on coordinator; no daemonless SSH executor is
    # part of the active topology.
    executors = { };

    # Native journald datagrams so TALLY_EVENT / TALLY_TASK_UUID /
    # TALLY_EXIT_CODE are real journal FIELDS, not keys inside a JSON blob in
    # MESSAGE. This is what makes the NAS-side journal archive queryable —
    # `journalctl SYSLOG_IDENTIFIER=tally TALLY_EVENT=failed` works on the
    # uploaded stream (2026-08-21, from the tally-vs-rewire review).
    journald.native = true;

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

    # One low-priority durable row replaces the old 02:00/03:30/04:30/06:00 chain.
    # It holds the build and coordinator GPU lanes end-to-end, making the measured
    # single-node build plus activation one exclusive maintenance window.
    # The system service handles Zenbook's successful offline/low-power skip internally.
    producers = lib.optionalAttrs isCoordinator {
      # call-record and call-diarize-backfill drop complete EnqueuePayload files
      # into tally's shared events directory. tally-drain.timer already claims
      # that directory every five seconds, so this entry declares the producer
      # contract without rendering a competing drain unit or timer.
      call-diarization = {
        kind = "events-dir";
        selfDrain = false;
      };

      # Local CLI writes are immediate; this low-priority pass only refreshes
      # inbound Google changes and re-projects Tally's producer schedules.
      dcal-sync = {
        kind = "calendar";
        onCalendar = "*-*-* *:07:00";
        enqueue = {
          argv = [
            "${lib.getExe pkgs.dcal}"
            "sync"
          ];
          pool = "local-ai-review";
          priority = "low";
          dedupKey = "dcal-sync-%Y-%m-%d-%H";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

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
          pool = "coordinator-nas-io";
          argv = systemService "journal-archive.service";
          priority = "low";
          dedupKey = "weekly-journal-archive-%Y-%W";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

      # nightly-fleet-deploy REMOVED 2026-08-21 with fleet-deploy.service
      # itself (see hosts/coordinator/default.nix) — superseded by the NAS
      # update-center. The future coordinator-side "pull when published"
      # producer should be a build-effect or pool-reachability kind, not a
      # calendar racing the NAS's build window.
    };
  };

  # Journal-noise filter for the 5s drain tick (2026-08-21). Measured on a
  # live 24h window: the drain's lifecycle lines ("Started"/"Finished", two
  # per tick, 17,280 ticks/day) were ~35k of the coordinator's ~43k daily
  # journal lines — ~10x everything else COMBINED (next talkers: system
  # manager 3.3k, kernel 1.0k, resolved 0.4k). Tom's criterion: "if tally is
  # exceptionally noisy, we will add the filter" — it is, so: LogLevelMax
  # caps this one unit at notice, dropping the info-level lifecycle chatter
  # from journald (and therefore from the NAS upload stream) while errors and
  # warnings still land. Tally's own job-event records are emitted by the
  # DAEMON with SYSLOG_IDENTIFIER=tally and are untouched. The interval
  # itself is hardcoded upstream (home-manager.nix OnUnitActiveSec=5s); the
  # eventual real fix is a systemd .path unit on the events dir instead of
  # polling — an upstream tally design change, tracked there, not here.
  systemd.user.services.tally-drain.Service.LogLevelMax = "notice";

}
