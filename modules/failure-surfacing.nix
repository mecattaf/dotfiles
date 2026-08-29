{
  config,
  lib,
  pkgs,
  ...
}:
# Fleet-wide surfacing of process crashes and unit failures — refs #134.
#
# The defect #134 records is not that things crashed; it is that nothing said
# so. Two crash bursts (a voxtype config-debugging session and four unexplained
# tally-daemon SIGABRTs at midnight) went unnoticed for weeks and were finally
# found by running `du` on the coredump directory.
#
# Three nets, because one does not cover the ground:
#
#   1. A systemd top-level drop-in (systemd.unit(5), "Top level drop-ins")
#      installs OnFailure=failure-notify@%N.service on EVERY system service —
#      including generated and transient ones, which a Nix-side map over
#      config.systemd.services would miss. Push-based and instant.
#   2. A journal tripwire on coredumps. systemd-coredump@ instances write a
#      journal event rather than failing a unit, so no OnFailure can fire for
#      them; the crashing process may not even be a service.
#   3. A journal tripwire on user-manager unit failures. The top-level drop-in
#      is a system-manager file and does not reach per-user units — which is
#      exactly where #134's burst 2 (tally-daemon) lived.
#
# Everything lands in one marker directory, extending the fleet-deploy failure
# marker that already exists rather than inventing a second channel: one file
# per failing unit (so a flapping unit rewrites its own marker instead of
# accumulating). A new marker episode is surfaced once per user on interactive
# fish login; a durable marker is not repeated in every later terminal.
let
  cfg = config.myFailureSurfacing;

  # Same name in every directory: systemd applies drop-ins by filename across
  # the precedence chain, so a unit-specific file of this name overrides the
  # type-level one. Pointing that override at /dev/null is how a unit opts out.
  dropinName = "10-fleet-onfailure.conf";

  maskedUnits = [
    # The handler must not handle its own failure; systemd tries to detect such
    # recursion but the manual tells us to break the chain explicitly.
    "failure-notify@.service"
  ]
  ++ cfg.excludeUnits;

  onFailureDropin = pkgs.runCommand "fleet-onfailure-dropin" { } ''
    d="$out/lib/systemd/system"
    mkdir -p "$d/service.d"
    printf '[Unit]\nOnFailure=failure-notify@%%N.service\n' > "$d/service.d/${dropinName}"
    ${lib.concatMapStringsSep "\n" (unit: ''
      mkdir -p "$d/${unit}.d"
      ln -s /dev/null "$d/${unit}.d/${dropinName}"
    '') maskedUnits}
  '';

  notifier = pkgs.writeShellScript "failure-notify" ''
    set -eu
    unit="''${1:?usage: failure-notify <unit>}"
    dir=${lib.escapeShellArg cfg.markerDir}
    safe="$(${pkgs.coreutils}/bin/printf '%s' "$unit" | ${pkgs.coreutils}/bin/tr / _)"
    when="$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M')"

    ${pkgs.coreutils}/bin/install -d -m 0755 "$dir"
    exec 9>"$dir/.failure-marker-reconcile.lock"
    ${pkgs.util-linux}/bin/flock 9
    ${pkgs.coreutils}/bin/printf '%s failed at %s — journalctl -u %s -b\n' \
      "$unit" "$when" "$unit" > "$dir/$safe"
    ${pkgs.coreutils}/bin/chmod 0644 "$dir/$safe"

    # Fields, not prose: the NAS journal copy can then answer "which units
    # failed this week" without parsing sentences.
    ${pkgs.coreutils}/bin/printf '%s\n' \
      "MESSAGE=unit failure surfaced: $unit" \
      "PRIORITY=3" \
      "SYSLOG_IDENTIFIER=failure-notify" \
      "FAILED_UNIT=$unit" \
      "DECISION=marker-written" | ${pkgs.util-linux}/bin/logger --journald || true
  '';

  markerReconciler = pkgs.writeShellApplication {
    name = "failure-marker-reconcile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ./failure-marker-reconcile.sh;
  };

  markerReporter = pkgs.writeShellApplication {
    name = "failure-marker-report";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.util-linux
    ];
    text = builtins.readFile ./failure-marker-report.sh;
  };

  journalWatcher =
    {
      kind,
      label,
      match,
      description,
      excludeField ? null,
      excludeValues ? [ ],
      excludeRegexField ? null,
      excludeRegexPatterns ? [ ],
    }:
    {
      inherit description;
      valueField = "EVENT_COUNT";
      # One new matching entry is the whole signal; there is nothing to sustain
      # and nothing to suppress, so the tripwire fires on the poll that sees it
      # and re-arms on the first quiet poll.
      #
      # But "re-arms on the first quiet poll" assumed a one-off crash. A unit
      # flapping at (or faster than) the poll cadence never grants a quiet
      # poll, so the watcher latched disarmed — 8 days blind on the
      # coordinator (#245), swallowing not just the flapper but every OTHER
      # failure on the box. The renotify floor bounds that blindness: a
      # condition still over-threshold this long after a fire fires again.
      threshold = 1;
      rearm = 1;
      sustainSeconds = 0;
      refractorySeconds = 0;
      renotifySeconds = cfg.renotifySeconds;
      intervalSeconds = cfg.checkSeconds;
      onBootSec = "5min";
      stateDirectory = "tripwire/${kind}";

      sensorPath = [
        pkgs.coreutils
        pkgs.jq # counts entries, not lines, and reduces each to its first line
        pkgs.systemd
      ];
      sensor = builtins.readFile ./tripwire-journal-sensor.sh;

      onFirePath = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      onFire = builtins.readFile ./tripwire-journal-onfire.sh;

      environment =
        {
          JOURNAL_KIND = kind;
          JOURNAL_LABEL = label;
          JOURNAL_MATCH = match;
          FAILURE_MARKER_DIR = cfg.markerDir;
        }
        // lib.optionalAttrs (excludeField != null && excludeValues != [ ]) {
          JOURNAL_EXCLUDE_FIELD = excludeField;
          JOURNAL_EXCLUDE_VALUES = lib.concatStringsSep " " excludeValues;
        }
        // lib.optionalAttrs (excludeRegexField != null && excludeRegexPatterns != [ ]) {
          JOURNAL_EXCLUDE_REGEX_FIELD = excludeRegexField;
          JOURNAL_EXCLUDE_REGEX_PATTERNS = builtins.toJSON excludeRegexPatterns;
        };
    };

  # systemd catalog message IDs, both verified live on the coordinator journal.
  coredumpMessageId = "fc2e22bc6ee647b6b90729ab34a250b1";
  unitFailedMessageId = "be02cf6855d2428ba40df7e9d022f03d";
in
{
  imports = [ ./tripwire.nix ];

  options.myFailureSurfacing = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Surface unit failures and coredumps instead of letting them pass silently.";
    };

    markerDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/failure-markers";
      description = ''
        Where failure markers land, one file per failing unit or watcher.
        (Until 2026-08-21 this was /var/lib/fleet-deploy/failed, piggybacking
        on the nightly fleet-deploy's marker channel; that service is gone —
        superseded by the NAS update-center — and this module is now the one
        and only "something needs your attention" channel on the fleet. The
        old directory may linger on hosts deployed before the rename; remove
        it by hand.)
      '';
    };

    excludeUnits = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Units that opt out of the blanket OnFailure=, by full unit name. A
        top-level drop-in is additive, so a unit with its own OnFailure= would
        otherwise report twice.
      '';
    };

    watchCoredumps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Surface new coredumps, which are journal events no OnFailure= can catch.";
    };

    coredumpExcludeComms = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Process names (COREDUMP_COMM) whose coredumps are not surfaced. For a
        process that crashes routinely and recovers on its own, every dump
        rewrites the marker and the channel goes permanently red — burying the
        one-off crashes this watcher exists to catch.
      '';
    };

    coredumpExcludeCmdlinePatterns = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Regular expressions matched against COREDUMP_CMDLINE. Use this for a
        deliberately crashing test whose generated process name is unstable;
        keep the expression narrow enough that a production process cannot
        match it. Invalid expressions fail open and surface the coredump.
      '';
    };

    watchUserUnitFailures = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Surface failures of per-user units, which the system-manager drop-in cannot reach.";
    };

    userUnitExcludeUnits = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = ''
        Per-user units (USER_UNIT) whose failures are not surfaced. Meant for a
        high-cadence tick that self-heals on its next run, where the sustained
        condition has its own detection; each entry should cite the issue
        tracking the fix that lets it come back off this list.
      '';
    };

    userManagerUids = lib.mkOption {
      type = with lib.types; listOf int;
      default = [ 1000 ];
      description = "UIDs whose user managers are watched for unit failures.";
    };

    checkSeconds = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Cadence of the journal watchers. Crashes are already durable in the journal, so this is about notice, not capture.";
    };

    renotifySeconds = lib.mkOption {
      type = lib.types.int;
      default = 21600;
      description = ''
        How long a watcher may stay continuously over-threshold after a fire
        before it fires again (#245). Bounds the blindness a flapping unit
        can inflict: 6 hours means at worst 4 reminders a day instead of one
        report ever. 0 restores the unbounded latch.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.packages = [ onFailureDropin ];

    systemd.services."failure-notify@" = {
      description = "Record the failure of %i";
      serviceConfig = {
        Type = "oneshot";
        # A notifier that can itself fail would need a notifier. The "-" prefix
        # makes any non-zero exit a success, which also keeps a failure during
        # early boot (before /var is writable) from cascading.
        ExecStart = "-${notifier} %i";
      };
    };

    systemd.services."failure-marker-reconcile" = {
      description = "Clear recovered unit-failure markers";
      after = map (uid: "user@${toString uid}.service") cfg.userManagerUids;
      environment = {
        FAILURE_MARKER_DIR = cfg.markerDir;
        USER_MANAGER_UIDS = lib.concatMapStringsSep " " toString cfg.userManagerUids;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${markerReconciler}/bin/failure-marker-reconcile";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "-${cfg.markerDir}" ];
        RestrictAddressFamilies = [ "AF_UNIX" ];
        TimeoutStartSec = "30s";
      };
    };

    systemd.timers."failure-marker-reconcile" = {
      description = "Reconcile recovered unit-failure markers";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "7min";
        OnUnitActiveSec = "${toString cfg.checkSeconds}s";
        AccuracySec = "30s";
      };
    };

    myTripwire.coredump =
      journalWatcher {
        kind = "coredump";
        label = "coredump(s)";
        match = "MESSAGE_ID=${coredumpMessageId}";
        description = "Surface coredumps recorded since the last check";
        excludeField = "COREDUMP_COMM";
        excludeValues = cfg.coredumpExcludeComms;
        excludeRegexField = "COREDUMP_CMDLINE";
        excludeRegexPatterns = cfg.coredumpExcludeCmdlinePatterns;
      }
      // {
        enable = cfg.watchCoredumps;
      };

    myTripwire.user-unit-failure =
      journalWatcher {
        kind = "user-unit-failure";
        label = "user unit failure(s)";
        # journalctl ANDs matches on different fields and ORs them on the same
        # field, so this reads: a unit-failed event, reported by any of these
        # user managers.
        match = lib.concatStringsSep " " (
          [ "MESSAGE_ID=${unitFailedMessageId}" ]
          ++ map (uid: "_SYSTEMD_UNIT=user@${toString uid}.service") cfg.userManagerUids
        );
        description = "Surface per-user unit failures recorded since the last check";
        excludeField = "USER_UNIT";
        excludeValues = cfg.userUnitExcludeUnits;
      }
      // {
        enable = cfg.watchUserUnitFailures;
      };

    programs.fish.interactiveShellInit = lib.mkAfter ''
      if status is-interactive
          set -l __new_failure_episodes \
              (${markerReporter}/bin/failure-marker-report ${lib.escapeShellArg cfg.markerDir} 2>/dev/null)
          if test $status -eq 0; and test (count $__new_failure_episodes) -gt 0
              set_color -o red; echo "⚠  new failure episode(s):"; set_color normal
              for __episode in $__new_failure_episodes
                  echo "   • "$__episode
              end
              echo "   shown once; details remain in journalctl"
          end
      end
    '';
  };
}
