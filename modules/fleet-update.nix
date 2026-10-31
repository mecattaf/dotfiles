{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = builtins.elem config.networking.hostName [
    "nas"
    "strix-coordinator"
  ];
  program = ../home/dot_local/bin/fleet-update;
  runtimeInputs = with pkgs; [
    python3
    git
    nix
    openssh
    coreutils
    util-linux
    systemd
  ];
  target = pkgs.writeShellApplication {
    name = "fleet-update-target";
    inherit runtimeInputs;
    text = ''exec python3 ${program} --target-activate "$@"'';
  };
  assess = pkgs.writeShellApplication {
    name = "fleet-update-assess";
    inherit runtimeInputs;
    text = ''exec python3 ${program} --target-assess "$@"'';
  };
  probe = pkgs.writeShellApplication {
    name = "fleet-update-probe";
    inherit runtimeInputs;
    text = ''
      export PATH="/etc/profiles/per-user/tom/bin:$PATH"
      exec python3 ${program} --target-probe
    '';
  };
  verify = pkgs.writeShellApplication {
    name = "fleet-update-verify";
    inherit runtimeInputs;
    text = ''exec python3 ${program} --target-verify "$@"'';
  };
  cli = pkgs.writeShellApplication {
    name = "fleet-update";
    runtimeInputs = runtimeInputs ++ [ pkgs.gh ];
    text = ''
      export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/tom/bin:$PATH"
      exec python3 ${program} "$@"
    '';
  };
  start = pkgs.writeShellApplication {
    name = "fleet-update-start";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      if (( $# > 1 )) || [[ "''${1:---json}" != --json ]]; then
        echo 'usage: fleet-update-start [--json]' >&2
        exit 2
      fi
      fleet_uid="$(id -u)"
      export XDG_RUNTIME_DIR="/run/user/$fleet_uid"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      ${cli}/bin/fleet-update --request --json >/dev/null
      systemctl --user start --no-block fleet-update.service
      echo '{"status":"starting","service":"fleet-update.service","ok":false}'
    '';
  };
  versions = {
    tailscale = config.services.tailscale.package.version;
  }
  // lib.optionalAttrs (config.myFleet.has "brain") {
    claude = pkgs.llm-agents.claude-code.version;
    codex = pkgs.llm-agents.codex.version;
    dsh = pkgs.llm-agents.dsh.version;
  };
in
{
  config = lib.mkIf enabled {
    assertions = lib.optionals (config.myFleet.has "brain") (
      map
        (name: {
          assertion =
            builtins.hasAttr name pkgs.llm-agents
            && !(pkgs.llm-agents.${name}.meta.broken or false)
            && (pkgs.llm-agents.${name}.meta.available or true);
          message = "Nightly updates require the Nix package ${name}; it must not be silently filtered out.";
        })
        [
          "claude-code"
          "codex"
          "dsh"
        ]
    );
    environment.systemPackages = [
      target
      assess
      probe
      verify
      cli
      start
    ];
    security.sudo.extraRules = [
      {
        users = [ "tom" ];
        commands = [
          {
            command = "${target}/bin/fleet-update-target";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${assess}/bin/fleet-update-assess";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    system.systemBuilderCommands = ''
      printf '%s\n' ${lib.escapeShellArg (builtins.toJSON versions)} > "$out/fleet-update-versions.json"
    '';
    # The single Floor trigger starts this fixed command through the trusted
    # maintenance plugin, not through model bash. It needs NAS SSH/GitHub auth
    # and the narrow sudo helper, so it must not inherit the harness sandbox or
    # its NoNewPrivileges. No timer, calendar, WantedBy or boot activation.
    home-manager.users.tom.systemd.user.services = lib.mkIf (config.networking.hostName == "nas") {
      fleet-update = {
        Unit = {
          Description = "Resumable nightly Nix fleet transaction (Floor admitted)";
          X-SwitchMethod = "keep-old";
        };
        Service = {
          Type = "simple";
          ExecStart = "${cli}/bin/fleet-update --worker --json";
          Environment = [
            "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/tom/bin:/home/tom/.local/bin"
          ];
          NoNewPrivileges = false;
          UMask = "0077";
          Nice = 19;
          IOSchedulingClass = "idle";
          MemoryMax = "1G";
          Restart = "no";
          TimeoutStopSec = 30;
        };
      };
    };
  };
}
