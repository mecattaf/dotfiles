{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Laptop catch-up leg for the nightly fleet transaction (fleet-deploy.nix).
#
# The nightly runs at 02:00 and treats an offline zenbook-duo as a successful
# skip — correct for the core, but Tom does not leave the laptop on overnight,
# so in practice it NEVER caught the train and drifted weeks behind (observed
# 2026-08-03: a June generation). This timer is the daytime retry: ONCE a day
# (Tom's 2026-08-03 cadence ruling — a 30-minute poll was overkill), if the
# laptop happens to be reachable and behind the last built candidate, push
# that exact candidate to it; otherwise it simply waits for tomorrow.
#
# Doctrine constraints, deliberately kept:
#   - EXACT CANDIDATE: the wanted profile comes from the newest
#     candidate-*.manifest (locked main ref + rolling override URLs), never
#     from re-resolving moving refs. The laptop gets byte-for-byte what the
#     nightly built.
#   - NEVER BUILDS: `nix build --max-jobs 0` only reuses the local store /
#     substituters. If the candidate was never built (a failed nightly), this
#     exits quietly — building belongs to the nightly under its tally lease,
#     not to a timer that may fire during interactive GPU work.
#   - Same power rules as the nightly: mains, or battery >= 50%.
#   - Failures surface via the fleet-wide OnFailure drop-in (#134); offline
#     and not-yet-built are quiet successful skips, mirroring the nightly.
let
  system = pkgs.stdenv.hostPlatform.system;
  deployPackage = inputs.deploy-rs.packages.${system}.deploy-rs;

  catchupScript = pkgs.writeShellApplication {
    name = "zenbook-catchup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.openssh
      pkgs.nix
      deployPackage
      pkgs.systemd
    ];
    text = ''
      # Never race the nightly transaction itself.
      if systemctl --quiet is-active fleet-deploy.service; then
        echo "zenbook-catchup: fleet-deploy is active; skipping"
        exit 0
      fi

      ssh_args=(-o BatchMode=yes -o ConnectTimeout=5)

      if ! ssh "''${ssh_args[@]}" -n root@zenbook-duo /run/current-system/sw/bin/true 2>/dev/null; then
        echo "zenbook-catchup: zenbook-duo offline; skipping"
        exit 0
      fi

      manifest="$(find /var/lib/fleet-deploy -maxdepth 1 -name 'candidate-*.manifest' \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
      if [ -z "$manifest" ]; then
        echo "zenbook-catchup: no candidate manifest yet; skipping"
        exit 0
      fi

      main_ref="$(grep '^main=' "$manifest" | cut -d= -f2-)"
      override_args=()
      while IFS='=' read -r name url; do
        [ "$name" = main ] && continue
        override_args+=(--override-input "$name" "$url")
      done < "$manifest"

      # Evaluate the candidate's laptop profile WITHOUT building: max-jobs 0
      # succeeds only when the nightly (or the store/cache) already has it.
      if ! wanted="$(nix build --no-link --print-out-paths --max-jobs 0 \
        "$main_ref#deploy.nodes.zenbook-duo.profiles.system.path" \
        "''${override_args[@]}" 2>/dev/null)"; then
        echo "zenbook-catchup: candidate profile not prebuilt; leaving it to the nightly"
        exit 0
      fi

      current="$(ssh "''${ssh_args[@]}" -n root@zenbook-duo readlink -f /nix/var/nix/profiles/system || true)"
      if [ "$current" = "$wanted" ]; then
        echo "zenbook-catchup: zenbook-duo already on the candidate; nothing to do"
        exit 0
      fi

      # Same power probe as the nightly: mains, or battery >= 50%.
      set +e
      ssh "''${ssh_args[@]}" root@zenbook-duo /bin/sh -s <<'POWER_PROBE'
      for ps in /sys/class/power_supply/*; do
        [ -r "$ps/type" ] || continue
        case "$(cat "$ps/type")" in
          Mains)
            [ "$(cat "$ps/online" 2>/dev/null)" = "1" ] && exit 0
            ;;
          Battery)
            cap="$(cat "$ps/capacity" 2>/dev/null)" || continue
            [ -n "$cap" ] && [ "$cap" -ge 50 ] && exit 0
            ;;
        esac
      done
      exit 10
      POWER_PROBE
      power_status=$?
      set -e
      if [ "$power_status" = 10 ]; then
        echo "zenbook-catchup: on battery below 50%; skipping"
        exit 0
      elif [ "$power_status" != 0 ]; then
        echo "zenbook-catchup: power probe failed with status $power_status" >&2
        exit "$power_status"
      fi

      echo "zenbook-catchup: deploying $wanted (was $current)"
      deploy --skip-checks --targets "$main_ref#zenbook-duo" -- "''${override_args[@]}"
      echo "zenbook-catchup: done"
    '';
  };
in
{
  config = lib.mkIf config.mySecrets.enable {
    systemd.services.zenbook-catchup = {
      description = "Push the last built fleet candidate to a zenbook that slept through the nightly";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "tom";
        Environment = [ "HOME=/home/tom" ];
        ExecStart = lib.getExe catchupScript;
      };
    };
    systemd.timers.zenbook-catchup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # One daytime attempt; unreachable postpones to the next day. The
        # hour is a guess at when the laptop is plausibly awake — adjust
        # freely, nothing else keys off it.
        OnCalendar = "11:00";
        RandomizedDelaySec = "30min";
        Persistent = true;
      };
    };
  };
}
