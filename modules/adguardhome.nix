{
  config,
  lib,
  pkgs,
  ...
}:
# NAS DNS policy. AdGuard owns loopback + LAN; resolved owns its own loopback
# stub and the tailnet listener. A missing tailnet address cannot prevent
# AdGuard from starting. Filter history and the retired workaround live in Git.
let
  isLanResolver = config.networking.hostName == "nas";
  coordinatorAddr = if isLanResolver then "10.42.0.2" else "127.0.0.1";
  internalNames = [
    "photos.internal"
    "music.internal"
    "videos.internal"
    "paperless.internal"
  ];
in
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    host = "127.0.0.1";
    port = 3000;
    openFirewall = false;
    settings = {
      dns = {
        bind_hosts = [
          "127.0.0.1"
        ]
        ++ lib.optionals isLanResolver [ "10.42.0.1" ];
        port = 53;
        upstream_dns = [
          "https://1.1.1.1/dns-query"
          "https://1.0.0.1/dns-query"
          "https://9.9.9.9/dns-query"
        ];
        bootstrap_dns = [
          "1.1.1.1"
          "9.9.9.9"
        ];
        upstream_mode = "load_balance";

        fallback_dns = [
          "9.9.9.9"
          "149.112.112.112"
        ];

        cache_enabled = true;
        cache_size = 4194304; # bytes; AdGuard's default, pinned
        cache_optimistic = true;

        enable_dnssec = true;

        edns_client_subnet.enabled = false;

        ratelimit = 100;
        ratelimit_subnet_len_ipv4 = 32;
        ratelimit_subnet_len_ipv6 = 64;
        ratelimit_whitelist = [
          "127.0.0.1"
        ]
        ++ lib.optionals isLanResolver [
          "10.42.0.1"
          "10.42.0.2" # coordinator
          "10.42.0.5" # worker
        ];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;

        rewrites = map (domain: {
          enabled = true;
          inherit domain;
          answer = coordinatorAddr;
        }) internalNames;
      };

      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
        {
          enabled = true;
          id = 2;
          name = "Steven Black hosts";
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        }
        {
          enabled = true;
          id = 3;
          name = "Hagezi Pro";
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
        }
        {
          enabled = true;
          id = 4;
          name = "Hagezi Threat Intelligence Feeds (medium)";
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.medium.txt";
        }
      ];

      querylog = {
        enabled = true;
        file_enabled = true;
        interval = "720h"; # 30 days
      };
      statistics = {
        enabled = true;
        interval = "2160h"; # 90 days, up from AdGuard's 24h default
      };
    };
  };

  services.resolved.settings.Resolve = {
    DNS = "127.0.0.1";
    Domains = "~.";
    # resolved uses freebind: tailnet enrollment is not a LAN DNS dependency.
    DNSStubListenerExtra = lib.optionals isLanResolver [ "100.64.0.1" ];
  };

  networking.hosts = lib.optionalAttrs isLanResolver {
    ${coordinatorAddr} = internalNames;
  };

  systemd.services.adguardhome = lib.mkIf isLanResolver {
    after = [
      "NetworkManager-ensure-profiles.service"
      "systemd-resolved.service"
    ];
    wants = [ "NetworkManager-ensure-profiles.service" ];
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-adguard-lan" ''
      for _ in $(${pkgs.coreutils}/bin/seq 30); do
        if ${pkgs.iproute2}/bin/ip -4 addr show dev enp1s0 | ${pkgs.gnugrep}/bin/grep -q '10\.42\.0\.1/'; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "NAS LAN address unavailable" >&2
      exit 1
    '';
  };

  networking.firewall.interfaces.tailscale0 = lib.mkIf isLanResolver {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [ 53 ];
  };
}
