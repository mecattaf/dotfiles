{
  config,
  lib,
  pkgs,
  ...
}:
# ADDITIONAL SaaS identity. Never import headscale.nix into this container,
# change the host's tailscaled, or share its socket/state. Root integrates
# this opt-in module; enrollment and SaaS policy approval are separate steps.
let
  cfg = config.myNas.tailscalePersonal;
  name = "nas-saas";
  iface = "ve-${name}";
  hostAddress = "172.31.255.1";
  localAddress = "172.31.255.2";
  lanAddress = "10.42.0.1";
  mediaPorts = lib.optionals cfg.media.enable [
    4533
    32400
  ];
  privatePorts = mediaPorts ++ lib.optional cfg.media.https.enable 443;
  hostPorts = mediaPorts ++ lib.optional cfg.media.https.enable 8443;
  ports = xs: lib.concatStringsSep ", " (map toString xs);
  hostAdmissions = prefix: ''
    ${prefix}ip saddr ${localAddress} ip daddr ${lanAddress} udp dport 53 accept
    ${prefix}ip saddr ${localAddress} ip daddr ${lanAddress} tcp dport 53 accept
    ${lib.optionalString (hostPorts != [ ]) ''
      ${prefix}ip saddr ${localAddress} ip daddr ${hostAddress} tcp dport { ${ports hostPorts} } accept
    ''}
    ${lib.optionalString cfg.funnel.enable ''
      ${prefix}ip saddr ${localAddress} ip daddr ${lanAddress} tcp dport 8090 accept
    ''}
  '';
  preferences = [
    "--accept-dns=false"
    "--accept-routes=false"
    "--ssh=false"
    "--advertise-routes="
    "--advertise-exit-node=${lib.boolToString cfg.advertiseExitNode}"
  ];
  # Each TCP relay has one immutable backend, not a general forward proxy.
  relay = listen: target: {
    socket = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = listen;
        NoDelay = true;
      };
    };
    service = {
      requires = [ ];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${target}";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };
  };
  relays =
    lib.optionalAttrs cfg.media.enable {
      personal-music = relay "0.0.0.0:4533" "${hostAddress}:4533";
      personal-plex = relay "0.0.0.0:32400" "${hostAddress}:32400";
    }
    // lib.optionalAttrs cfg.media.https.enable {
      personal-media-tls = relay "0.0.0.0:443" "${hostAddress}:8443";
    }
    // lib.optionalAttrs cfg.funnel.enable {
      # Funnel's ONLY target. Never target the private TLS/media relay.
      personal-headscale = relay "127.0.0.1:18090" "${lanAddress}:8090";
    };
in
{
  options.myNas.tailscalePersonal = {
    enable = lib.mkEnableOption "isolated additional NAS membership in Tom's SaaS tailnet";
    advertiseExitNode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Advertise exit capability; admin approval and each client's opt-in remain required. Never consume an exit route on the NAS.";
    };
    media = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Private Navidrome/Plex TCP proxies only; SaaS ACLs must restrict their authorized audience.";
      };
      https = {
        enable = lib.mkEnableOption "private media HTTPS on SaaS port 443 using a host-owned ACME certificate";
        musicHostname = lib.mkOption {
          type = lib.types.strMatching "[a-z0-9][a-z0-9.-]*\\.[a-z]+";
          default = "music.mecattaf.dev";
          description = "Private DNS name resolving to the NEW SaaS node, never a public Funnel target.";
        };
        plexHostname = lib.mkOption {
          type = lib.types.strMatching "[a-z0-9][a-z0-9.-]*\\.[a-z]+";
          default = "plex.mecattaf.dev";
          description = "Private DNS name resolving to the NEW SaaS node.";
        };
        acmeHost = lib.mkOption {
          type = lib.types.str;
          default = "mecattaf.dev";
          description = "Existing host security.acme.certs entry covering BOTH media names. This module neither obtains DNS credentials nor adds certificate SANs.";
        };
      };
    };
    funnel = {
      enable = lib.mkEnableOption ''
        PUBLIC Headscale-only Funnel on the SaaS node's *.ts.net:8443.
        Requires separate SaaS Funnel permission/HTTPS enablement and reviewed
        Headscale server_url. This does not expose media or change server_url
      '';
      policyApproved = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Operator attestation that HTTPS/Funnel permission was granted to THIS node in the SaaS policy. Never authorize all members automatically.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.hostName == "nas";
        message = "tailscalePersonal is NAS-only.";
      }
      {
        assertion = config.networking.nftables.enable;
        message = "tailscalePersonal requires the NAS nftables firewall.";
      }
      {
        assertion = config.networking.firewall.enable;
        message = "tailscalePersonal requires the host firewall.";
      }
      {
        assertion = !(builtins.elem iface config.networking.firewall.trustedInterfaces);
        message = "Never trust the personal-tailnet veth.";
      }
      {
        assertion = !cfg.media.https.enable || cfg.media.enable;
        message = "Private media HTTPS requires media.enable.";
      }
      {
        assertion =
          !cfg.media.https.enable || cfg.media.https.musicHostname != cfg.media.https.plexHostname;
        message = "Music and Plex need distinct private hostnames.";
      }
      {
        assertion = !cfg.funnel.enable || cfg.funnel.policyApproved;
        message = "Approve node-scoped SaaS Funnel policy before enabling the public Headscale endpoint.";
      }
    ];

    # A separate root-owned state directory is easy to back up without ever
    # copying/replacing Headscale's /var/lib/tailscale. No enrollment key in Nix.
    systemd.tmpfiles.rules = [ "d /var/lib/tailscale-personal 0700 root root -" ];
    containers.${name} = {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      ephemeral = false;
      inherit hostAddress localAddress;
      bindMounts."/var/lib/tailscale" = {
        hostPath = "/var/lib/tailscale-personal";
        isReadOnly = false;
      };
      config = { lib, ... }: {
        system.stateVersion = "26.05";
        networking.useHostResolvConf = false;
        networking.nameservers = [ lanAddress ];
        services.resolved.enable = false;
        services.openssh.enable = false;
        networking.nftables.enable = true;
        # IPv4 uplink only: IPv6 tailnet traffic has no external v6 route.
        # Do not invent an IPv6 gateway or let it escape through the host.
        networking.firewall = {
          enable = true;
          checkReversePath = "loose";
          interfaces.tailscale0.allowedTCPPorts = privatePorts;
        };
        networking.nftables.tables.personal_ingress = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority -10; policy accept;
              iifname "lo" accept
              ct state { established, related } accept
              # tailscaled can install an accepting input chain. This early
              # DROP is final even if that later chain accepts all tailnet IPs.
              ${lib.optionalString (privatePorts != [ ]) ''
                iifname "tailscale0" tcp dport { ${ports privatePorts} } accept
              ''}
              # Exit clients use tailscaled's DNS server on the tailnet IP.
              iifname "tailscale0" udp dport 53 accept
              iifname "tailscale0" tcp dport 53 accept
              iifname "tailscale0" drop
              # No inbound host/LAN path to any private media listener.
              iifname "eth0" udp dport 41641 accept
              iifname "eth0" drop
            }
          '';
        };
        services.tailscale = {
          enable = true;
          interfaceName = "tailscale0";
          useRoutingFeatures = "server";
          openFirewall = true;
          disableTaildrop = true;
          extraUpFlags = preferences;
          extraSetFlags = preferences;
          # No authKeyFile, login-server, accept-route, Tailscale SSH, or
          # host state/socket share. Interactive enrollment is explicit.
        };
        systemd.services =
          (lib.mapAttrs (_: entry: entry.service) relays)
          // {
            tailscaled-set.serviceConfig.ExecCondition = pkgs.writeShellScript "personal-tailnet-enrolled" ''
              ${pkgs.tailscale}/bin/tailscale status --json --peers=false 2>/dev/null \
                | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null
            '';
          }
          // lib.optionalAttrs cfg.funnel.enable {
            personal-headscale-funnel = {
              description = "Public Headscale-only Funnel; never private NAS media";
              wantedBy = [ "multi-user.target" ];
              after = [
                "tailscaled.service"
                "personal-headscale.socket"
              ];
              wants = [
                "tailscaled.service"
                "personal-headscale.socket"
              ];
              serviceConfig = {
                # Foreground session: stopping this unit retracts this Funnel.
                # No --bg and no blanket 'funnel reset' touching other state.
                ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --https=8443 http://127.0.0.1:18090";
                Restart = "on-failure";
                RestartSec = "30s";
              };
            };
          };
        systemd.sockets = lib.mapAttrs (_: entry: entry.socket) relays;
      };
    };

    # A failed/stopped firewall must not leave a privileged router online.
    systemd.services."container@${name}" = {
      after = [
        "nftables.service"
        "systemd-tmpfiles-setup.service"
      ];
      bindsTo = [ "nftables.service" ];
      requires = [ "nftables.service" ];
      # BindsTo stops on firewall failure, but does not start us again.
      # PartOf propagates restart; WantedBy recovers explicit stop/start.
      # Only container -> After firewall orders these reciprocal needs.
      partOf = [ "nftables.service" ];
      wantedBy = [ "nftables.service" ];
    };

    # Host input admissions go through BOTH our early guard and nixos-fw.
    networking.firewall.extraInputRules = hostAdmissions ''iifname "${iface}" '';
    networking.firewall.extraForwardRules = ''
      iifname "${iface}" oifname "enp1s0" ip saddr ${localAddress} accept
    '';
    networking.nftables.tables.personal_isolation = {
      family = "inet";
      content = ''
        set non_internet_v4 {
          type ipv4_addr; flags interval;
          elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
            169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
            198.18.0.0/15, 224.0.0.0/4, 240.0.0.0/4 }
        }
        chain prerouting {
          type filter hook prerouting priority -155; policy accept;
          # skb marks survive veth traversal; do not inherit another
          # tailscaled's routing/firewall authority in the host namespace.
          iifname "${iface}" meta mark set 0
        }
        chain input {
          type filter hook input priority -10; policy accept;
          iifname != "${iface}" return
          ${hostAdmissions ""}
          counter drop
        }
        chain forward {
          type filter hook forward priority -10; policy accept;
          iifname "${iface}" jump from_personal
          oifname "${iface}" ct state { established, related } accept
          oifname "${iface}" counter drop
        }
        chain from_personal {
          meta nfproto != ipv4 counter drop
          ip saddr != ${localAddress} counter drop
          ip daddr @non_internet_v4 counter drop
          oifname != "enp1s0" counter drop
          accept
        }
      '';
    };
    networking.nftables.tables.personal_nat = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat + 5; policy accept;
          iifname "${iface}" oifname "enp1s0" ip saddr ${localAddress} snat to ${lanAddress}
        }
      '';
    };

    # All TLS private-key reads stay with the host Caddy. No cert/key bind
    # mount into the network container and no public media Funnel.
    services.caddy = lib.mkIf cfg.media.https.enable {
      enable = true;
      virtualHosts = lib.listToAttrs (
        map
          (entry: {
            name = "https://${entry.hostname}:8443";
            value = {
              listenAddresses = [ hostAddress ];
              useACMEHost = cfg.media.https.acmeHost;
              logFormat = "output discard";
              extraConfig = ''
                reverse_proxy 127.0.0.1:${toString entry.port}
              '';
            };
          })
          [
            {
              hostname = cfg.media.https.musicHostname;
              port = 4533;
            }
            {
              hostname = cfg.media.https.plexHostname;
              port = 32400;
            }
          ]
      );
    };
    systemd.services.caddy = lib.mkIf cfg.media.https.enable {
      # The host-veth address is assigned by the container's postStart.
      after = [ "container@${name}.service" ];
      requires = [ "container@${name}.service" ];
      bindsTo = [ "container@${name}.service" ];
      partOf = [ "container@${name}.service" ];
      wantedBy = [ "container@${name}.service" ];
    };

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "nas-personal-tailscale";
        runtimeInputs = [ pkgs.nixos-container ];
        text = ''
          exec nixos-container run ${name} -- tailscale "$@"
        '';
      })
      (pkgs.writeShellApplication {
        name = "nas-personal-enroll";
        runtimeInputs = [ pkgs.nixos-container ];
        text = ''
          # Explicit one-time interactive SaaS login. No auth key in argv,
          # Nix, logs, or Git; never operate the host's default socket.
          exec nixos-container run ${name} -- tailscale up ${lib.escapeShellArgs preferences}
        '';
      })
    ];
  };
}
