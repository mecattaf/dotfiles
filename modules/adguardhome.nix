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
    "browser.internal"
  ];

  # The artifact namespace, read from the one edit point rather than spelled
  # out. modules/artifacts-defaults.nix owns it; a literal here would be a
  # second place to forget when it changes, and this file already carries the
  # `.internal` names that have no such single source.
  artifacts = import ./artifacts-defaults.nix;

  # SPLIT HORIZON FOR ARTIFACTS (2026-09-11, R-15). Exactly the same trick the
  # `.internal` names above use, applied to a namespace that also exists in
  # public DNS. The tailnet rung publishes <slug>.<namespace> as an
  # unproxied record pointing at the coordinator's tailscale.com address — an
  # address the client cannot route to, because the client's tailnet is the
  # NAS's headscale and the two control planes share no netmap. On the LAN,
  # though, Caddy is already listening for these names on the coordinator's own
  # LAN interface (modules/caddy-artifacts.nix:86 opens :80 on wlp192s0), so
  # the only thing missing was a resolver willing to say so. This is that.
  #
  # AdGuard Home's `*.example` matches SUBDOMAINS only, never the apex, which is
  # what is wanted: every artifact slug resolves to 10.42.0.2 for anything
  # asking this resolver, and the apex itself is left to public DNS.
  #
  # Known and accepted: off-LAN the public record still answers an address the
  # client cannot reach. Off-LAN artifact viewing is a DEFERRED row (M-5,
  # DF-CLIENT-8), not a gap this commit pretends to close. Also accepted: for
  # LAN viewers this wildcard SHADOWS a slug that has been promoted to
  # Cloudflare Pages — Caddy 404s a slug with no drop-file — which is exactly
  # why the publish-artifact skill's rule is to keep the drop-file until the
  # Pages copy is confirmed.
  #
  # This does not reopen the "no per-device AdGuard" ruling in AGENTS.md: this
  # file is the LAN resolver, imported by the NAS alone, and the whole point is
  # that there is exactly one of it.
  artifactRewrite = {
    enabled = true;
    domain = "*.${artifacts.namespace}";
    answer = coordinatorAddr;
  };
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

        # The `.internal` front doors, then the artifact wildcard. Both point at
        # the coordinator; only the second one shadows a name that also exists
        # in public DNS (see artifactRewrite above).
        rewrites = (map (domain: {
          enabled = true;
          inherit domain;
          answer = coordinatorAddr;
        }) internalNames)
        ++ [ artifactRewrite ];
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
