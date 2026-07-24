{
  config,
  fleetDeploySshOpts,
  inputs,
  lib,
  pkgs,
  rollingInputOverrides,
  ...
}:
# One exact-candidate fleet transaction. Tally owns its calendar, durable row,
# proof, and the atomic build + two-GPU admission window; this oneshot owns
# only the deployment content. deploy-rs couples worker → coordinator activation
# with magic rollback. The Zenbook remains a later best-effort leg so an offline
# or low-battery laptop can never block the core pair.
let
  system = pkgs.stdenv.hostPlatform.system;
  deployPackage = inputs.deploy-rs.packages.${system}.deploy-rs;
  failureMarker = "/var/lib/fleet-deploy/fleet-deploy.service.fail";
  rollingResolution = lib.concatMapStringsSep "\n" (input: ''
    resolved="$(resolve_flake ${lib.escapeShellArg input.url})"
    override_args+=(--override-input ${lib.escapeShellArg input.name} "$resolved")
    printf '%s=%s\n' ${lib.escapeShellArg input.name} "$resolved" >> "$candidate_tmp"
  '') rollingInputOverrides;

  fleetDeploy = pkgs.writeShellApplication {
    name = "fleet-deploy";
    runtimeInputs = [
      config.nix.package
      deployPackage
      pkgs.attic-client
      pkgs.coreutils
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      # Run as the ordinary trusted Nix user so the existing Attic client login
      # continues to publish full closures; deploy-rs still activates as remote root.
      export HOME=/home/tom
      export XDG_CONFIG_HOME=/home/tom/.config

      state_dir=/var/lib/fleet-deploy
      candidate_tmp="$(mktemp "$state_dir/.candidate.XXXXXX")"
      cleanup() {
        local status=$?
        rm -f "$candidate_tmp" || true
        if (( status == 0 )); then
          rm -f ${lib.escapeShellArg failureMarker} || true
        fi
        exit "$status"
      }
      trap cleanup EXIT

      # Resolve each moving GitHub reference once. The returned canonical URL
      # contains both the commit and narHash, so every later eval/build/activation
      # in this transaction addresses one immutable candidate.
      resolve_flake() {
        nix flake metadata --json --refresh "$1" \
          | jq -er '.url | select(type == "string" and length > 0)'
      }

      main_ref="$(resolve_flake github:mecattaf/dotfiles/main)"
      printf 'main=%s\n' "$main_ref" > "$candidate_tmp"

      override_args=()
      ${rollingResolution}

      candidate_hash="$(sha256sum "$candidate_tmp" | cut -d ' ' -f 1)"
      candidate="$state_dir/candidate-$candidate_hash.manifest"
      install -m 0644 "$candidate_tmp" "$candidate"
      echo "fleet-deploy: exact candidate $candidate_hash"
      sed 's/^/fleet-deploy:   /' "$candidate"

      # Build the same deploy-rs-wrapped profile that will be copied and activated.
      # Coordinator's Nix daemon retains its worker distributed builder; local
      # split-horizon resolution keeps that traffic on Thunderbolt. The explicit
      # Attic push preserves the former cache warmer's full-closure mirror.
      build_profile() {
        local host="$1"
        local out

        echo "fleet-deploy: building $host"
        out="$(nix build --no-link --print-out-paths \
          "''${override_args[@]}" \
          "$main_ref#deploy.nodes.$host.profiles.system.path")"

        if [[ "$out" != /nix/store/* || "$out" == *$'\n'* ]]; then
          echo "fleet-deploy: $host returned an invalid profile path: $out" >&2
          return 1
        fi

        if ! timeout 120 attic push fleet "$out"; then
          # Cache publication has always been best-effort: deploy-rs can still
          # copy the closure or let the target use its configured substituters.
          echo "fleet-deploy: warning: Attic push failed for $host ($out)" >&2
        fi
      }

      build_profile worker
      build_profile coordinator

      # Preserve the old cache warmer's all-host behavior. A broken laptop build
      # is remembered but cannot prevent the already-built core from deploying.
      zenbook_build_ok=1
      if ! build_profile zenbook-duo; then
        zenbook_build_ok=0
        echo "fleet-deploy: zenbook-duo build failed; continuing with the core" >&2
      fi

      echo "fleet-deploy: activating rollback-coupled core (worker -> coordinator)"
      deploy --skip-checks \
        --targets "$main_ref#worker" "$main_ref#coordinator" \
        -- "''${override_args[@]}"

      if (( ! zenbook_build_ok )); then
        echo "fleet-deploy: core deployed, but the prebuilt laptop candidate failed" >&2
        exit 1
      fi

      # The laptop deliberately has no Tally daemon. Offline and low-power are
      # successful skips; after the online probe succeeds, transport/build/deploy
      # failures are real failures retained by the one parent Tally witness.
      ssh_args=( ${lib.escapeShellArgs fleetDeploySshOpts} )
      if ! ssh "''${ssh_args[@]}" -n root@zenbook-duo /run/current-system/sw/bin/true; then
        echo "fleet-deploy: zenbook-duo offline; core deployed, laptop skipped"
        exit 0
      fi

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

      case "$power_status" in
        0) ;;
        10)
          echo "fleet-deploy: zenbook-duo on battery below 50%; core deployed, laptop skipped"
          exit 0
          ;;
        *)
          echo "fleet-deploy: zenbook-duo power probe failed with status $power_status" >&2
          exit "$power_status"
          ;;
      esac

      echo "fleet-deploy: activating zenbook-duo"
      deploy --skip-checks --targets "$main_ref#zenbook-duo" -- "''${override_args[@]}"
      echo "fleet-deploy: candidate $candidate_hash deployed successfully"
    '';
  };

  failureNotifier = pkgs.writeShellScript "fleet-deploy-notify" ''
    marker=${lib.escapeShellArg failureMarker}
    ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/fleet-deploy
    ${pkgs.coreutils}/bin/printf 'fleet-deploy.service failed %s — journalctl -u fleet-deploy.service -b\n' \
      "$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M')" > "$marker"
    ${pkgs.coreutils}/bin/chmod 0644 "$marker"
  '';
in
{
  systemd.services = {
    fleet-deploy = {
      description = "Deploy one exact NixOS candidate across the Tally-admitted fleet";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # This service deploys the coordinator which is running it. Match the stock
      # nixos-upgrade unit's self-update protection so switch-to-configuration does
      # not restart the controller midway through deploy-rs confirmation.
      restartIfChanged = false;
      unitConfig = {
        OnFailure = "fleet-deploy-alert.service";
        X-StopOnRemoval = false;
      };

      serviceConfig = {
        Type = "oneshot";
        User = "tom";
        Group = "users";
        ExecStart = "${fleetDeploy}/bin/fleet-deploy";
        StateDirectory = "fleet-deploy";
        StateDirectoryMode = "0755";
        TimeoutStartSec = "infinity";
        Nice = 10;
      };
    };

    fleet-deploy-alert = {
      description = "Record a failed nightly fleet deployment";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = failureNotifier;
      };
    };
  };

  programs.fish.interactiveShellInit = lib.mkAfter ''
    if status is-interactive; and test -e ${failureMarker}
        set_color -o red; echo "⚠  fleet deploy FAILED:"; set_color normal
        echo "   • "(cat ${failureMarker})
        echo "   clear with: sudo rm ${failureMarker}"
    end
  '';
}
