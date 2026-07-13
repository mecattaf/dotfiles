{ ... }:
# Per-machine AdGuard Home — the fleet's DNS ad/tracker filter, ONE loopback
# instance per box. This replaces the old coordinator-only LAN quadlet that
# filtered DNS for the now-retired BE550 wifi segment; every host (coordinator,
# worker, zenbook-duo) now filters its OWN queries. Imported fleet-wide from
# modules/common.nix.
#
# Fully declarative: mutableSettings = false, so the entire config lives here in
# git and AdGuard NEVER runs its web setup wizard. AdGuardHome.yaml is
# regenerated from this on every rebuild; the UI at http://127.0.0.1:3000 is
# view-only (query log / stats), never the source of truth. Change a blocklist
# or rule HERE, not in the browser.
#
# Port-53 arrangement — the sensible, no-fighting approach: AdGuard binds
# LOOPBACK 127.0.0.1:53 ONLY (never 0.0.0.0), so it is not an open resolver and
# needs no firewall ports. systemd-resolved keeps its own stub on a DIFFERENT
# loopback IP (127.0.0.53:53) — no EADDRINUSE collision, so the old
# `DNSStubListener=no` hack is gone — and simply forwards everything to AdGuard
# as its upstream (DNS=127.0.0.1, Domains=~.). Resolution path:
#   app → nss-resolve → resolved (127.0.0.53) → AdGuard (127.0.0.1) → DoH upstream.
# Tailscale still injects *.ts.net as a more-specific per-link routing domain
# into resolved, so MagicDNS keeps winning for the tailnet — the reason we route
# through resolved instead of the naive `nameservers = [ "127.0.0.1" ]`, which
# would bypass resolved and break split-DNS across the mesh.
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false; # config is git, not the web wizard
    host = "127.0.0.1"; # web UI / query log — loopback only
    port = 3000;
    openFirewall = false; # loopback-only: nothing to expose

    settings = {
      # DNS resolver: loopback bind, DoH upstreams (encrypted end to end so the
      # ISP no longer sees plaintext lookups).
      #
      # The endpoints are IP-LITERAL DoH (1.1.1.1 / 9.9.9.9), not hostnames, on
      # purpose: a hostname endpoint (https://dns.cloudflare.com/…) makes AdGuard
      # first resolve that hostname over plain :53 via bootstrap_dns on every
      # cold start, so a network that filters outbound :53 (captive portals,
      # some hotel/guest LANs) would stall the resolver until bootstrap gives
      # up. An IP-literal endpoint connects straight to <ip>:443 with no :53
      # lookup at all — one less thing that can break on an unfamiliar network,
      # which matters for the roaming laptops. Verified live on the worker
      # 2026-07-13: resolves + filters through this exact config. bootstrap_dns
      # is kept only to satisfy the mutableSettings=false assertion (must be a
      # non-empty list) and as a fallback if a hostname endpoint is ever added;
      # it is not on the hot path today.
      dns = {
        bind_hosts = [ "127.0.0.1" ];
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
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };

      # Blocklists. AdGuard DNS filter is the network-level analog of the
      # AdGuard browser extension's base filter; Steven Black adds the classic
      # hosts-file coverage. IDs are arbitrary but must stay unique + stable.
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
      ];
    };
  };

  # Point resolved's upstream at AdGuard and make that route authoritative for
  # ALL names (~.), so no DHCP-pushed per-link DNS can slip past the filter.
  # resolved itself is enabled fleet-wide in common.nix; this only sets where it
  # forwards. Tailscale's ts.net domain is more specific, so MagicDNS still wins.
  services.resolved.settings.Resolve = {
    DNS = "127.0.0.1";
    Domains = "~.";
  };
}
