{
  config,
  lib,
  pkgs,
  freshPkgs,
  ...
}:
let
  cfg = config.services.herdr-web-ui;
  package = pkgs.callPackage ../pkgs/herdr-web-ui {
    inherit (cfg) revision sourceHash depsHash;
    bun = freshPkgs.bun; # upstream requires Bun >= 1.4
  };
in
{
  options.services.herdr-web-ui = {
    enable = lib.mkEnableOption "the brain's loopback Herdr web UI";
    revision = lib.mkOption {
      type = lib.types.str;
      default = "TODO-private-fork-rev"; # TODO(Tom): private fork rev
      description = "Full commit of the private mecattaf/herdr-web-ui fork (build/claude-morning).";
    };
    sourceHash = lib.mkOption {
      type = lib.types.str;
      default = lib.fakeHash;
      description = "fetchFromGitHub hash of the private fork revision.";
    };
    depsHash = lib.mkOption {
      type = lib.types.str;
      default = lib.fakeHash;
      description = "Recursive hash of the frozen Bun node_modules fetch.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myFleet.has "brain";
        message = "herdr-web-ui belongs on a brain host.";
      }
      {
        assertion =
          builtins.match "[0-9a-f]{40}" cfg.revision != null
          && cfg.sourceHash != lib.fakeHash
          && cfg.depsHash != lib.fakeHash;
        message = "TODO(Tom): private fork rev — publish build/claude-morning to the private mecattaf/herdr-web-ui fork and fill services.herdr-web-ui.{revision,sourceHash,depsHash} before deployment.";
      }
    ];

    home-manager.users.tom.systemd.user.services.herdr-web-ui = {
      Unit = {
        Description = "Herdr web UI (loopback, private Tailscale Serve)";
        After = [ "herdr.service" ];
        Wants = [ "herdr.service" ];
      };
      Service = {
        ExecStart = lib.getExe package;
        WorkingDirectory = "%h";
        Environment = [
          "HOST=127.0.0.1"
          "PORT=7317"
          "PATH=${
            lib.makeBinPath [
              pkgs.nodejs_24
              pkgs.openssh
              pkgs.git
              pkgs.tailscale
            ]
          }:/etc/profiles/per-user/tom/bin:/home/tom/.local/bin:/run/current-system/sw/bin"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        OOMPolicy = "continue";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Foreground Serve owns only this HTTPS listener; no reset of other
    # Serve/Funnel state, no Funnel, and the application never binds the LAN.
    systemd.services.herdr-web-ui-serve = {
      description = "Private Tailscale HTTPS for Herdr web UI";
      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.tailscale} serve --https=443 http://127.0.0.1:7317";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
  };
}
