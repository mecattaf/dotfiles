{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNasClient;
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
in
{
  options.myNasClient = {
    useRemoteStorage = lib.mkEnableOption "mounting the NAS NFS export at the historical /mnt/nas path";
    relayMedia = lib.mkEnableOption "relaying tailnet Immich and Navidrome traffic to the Ethernet-only NAS";
    # Separate gates, not additions to relayMedia: relayMedia is LIVE, and each
    # of these turns on with its own NAS-side gate in its own commit.
    relayAttic = lib.mkEnableOption "relaying the fleet binary cache to atticd on the NAS (#130 ws5)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.useRemoteStorage {
      boot.supportedFilesystems = [ "nfs" ];
      # soft/timeo/retrans are the load-bearing options: with the default hard
      # mount, a dead NAS makes every I/O on /mnt/nas retry FOREVER in the
      # kernel, and on 2026-08-02 that wedged PID 1 mid `nixos-rebuild switch`
      # long enough for the 30s hardware watchdog (modules/strix.nix) to reset
      # the box. soft + timeo=50 (5s/try, deciseconds) + retrans=2 bounds any
      # NFS op to ~15s worst case — an eternity on the dedicated /30 cable, so
      # EIO only ever surfaces when the NAS is genuinely down, where failing
      # beats hanging. No x-systemd.device-timeout: 'nas:/' is not a device
      # path, so systemd ignores it with a warning on every generator run.
      fileSystems."/mnt/nas" = {
        device = "nas:/";
        fsType = "nfs4";
        options = [
          "noatime"
          "nofail"
          "noauto"
          "soft"
          "timeo=50"
          "retrans=2"
          "x-systemd.automount"
          "x-systemd.mount-timeout=30s"
          "_netdev"
        ];
      };
    })

    (lib.mkIf cfg.relayMedia {
      assertions = [
        {
          assertion = !config.myCoordinatorMedia.enable;
          message = "coordinator media core and NAS relay cannot own ports 2283/4533 together";
        }
      ];

      systemd.sockets.immich-relay = {
        description = "Coordinator front door for Ethernet-only NAS Immich";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:2283";
          NoDelay = true;
        };
      };
      systemd.services.immich-relay = {
        description = "Relay Immich to nas:2283 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:2283";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.sockets.navidrome-relay = {
        description = "Coordinator front door for Ethernet-only NAS Navidrome";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:4533";
          NoDelay = true;
        };
      };
      systemd.services.navidrome-relay = {
        description = "Relay Navidrome to nas:4533 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:4533";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.sockets.plex-relay = {
        description = "Coordinator front door for Ethernet-only NAS Plex";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:32400";
          NoDelay = true;
        };
      };
      systemd.services.plex-relay = {
        description = "Relay Plex to nas:32400 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:32400";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      # Existing clients keep coordinator.tail8dd1.ts.net; only coordinator has
      # a Tailscale identity, and these sockets relay across the private cable.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        2283
        4533
        32400
      ];

      # Memorable intranet front doors ADDED on top of the port URLs, never
      # replacing them: photos/music/videos.internal resolve fleet-wide via
      # the per-box AdGuard rewrites (modules/adguardhome.nix) to this host's
      # tailnet IP, and Caddy (:80, tailscale0-only — see caddy-artifacts.nix)
      # hands them to the same socket relays the port URLs use. Plain HTTP by
      # the same v1 posture as the artifact plane: WireGuard is the transport
      # security and `.internal` never resolves publicly.
      services.caddy.virtualHosts = {
        "http://photos.internal".extraConfig = ''
          reverse_proxy 127.0.0.1:2283
        '';
        "http://music.internal".extraConfig = ''
          reverse_proxy 127.0.0.1:4533
        '';
        "http://videos.internal".extraConfig = ''
          # Plex answers 401 on its bare API root; the human entrance is /web.
          redir / /web/ 302
          reverse_proxy 127.0.0.1:32400
        '';
      };
    })

    # ── #130 ws5: binary-cache relay ─────────────────────────────────────────
    # Keeps every host's substituter URL at http://coordinator:8080/fleet
    # (modules/common.nix) while atticd itself moves to the NAS. Unlike the
    # media relays there is no wake proxy on the far side: the cache is in the
    # substituter hot path and must answer immediately (hosts/nas/attic.nix).
    (lib.mkIf cfg.relayAttic {
      assertions = [
        {
          # Both want tcp/8080 on this box. The coordinator's own atticd must be
          # off in the SAME commit that turns this on, or the relay socket
          # cannot bind — add `services.atticd.enable = lib.mkForce false;` to
          # hosts/coordinator/default.nix. Full sequence: the runbook header in
          # hosts/nas/attic.nix.
          assertion = !config.services.atticd.enable;
          message = "myNasClient.relayAttic and the coordinator's own atticd cannot both own port 8080; disable hosts/coordinator/attic.nix in the same commit (see the runbook in hosts/nas/attic.nix)";
        }
      ];

      systemd.sockets.attic-relay = {
        description = "Coordinator front door for the NAS-hosted fleet binary cache";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:8080";
          NoDelay = true;
        };
      };
      systemd.services.attic-relay = {
        description = "Relay the fleet binary cache to nas:8080 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:8080";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      # Same boundary hosts/coordinator/attic.nix used: mesh only, never wifi.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
    })
  ];
}
