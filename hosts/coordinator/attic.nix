{ config, lib, ... }:
# Fleet binary cache SERVER — atticd on the coordinator (conductor role, always-on).
# The ~7,744 llm-agents derivations build once on the designated builder (worker)
# and land here; every host then substitutes the prebuilt paths instead of the
# ~8h from-source rebuild. Reachable over the Tailscale mesh (pull from anywhere,
# no same-wifi requirement) and the TB5 fast lane for the Strix pair. refs #42.
#
# Gated on mySecrets.enable: atticd needs its RS256 JWT signing secret, delivered
# as an agenix EnvironmentFile (secrets/atticd-server-token.age, coordinator-only).
#
# sqlite + local storage under /var/lib/atticd (systemd StateDirectory) — no
# Postgres/object-store dependency; fine for a 3-host fleet.
#
# RUNTIME BOOTSTRAP (once, after the first switch that brings atticd up):
#   1. Create the cache:   atticd-atticadm ... OR from a logged-in client:
#        attic login local http://coordinator:8080 "$(atticd-atticadm make-token \
#          --sub fleet-admin --validity '10y' --pull '*' --push '*' --create-cache '*')"
#        attic cache create fleet
#   2. Make it public so pulls need no per-client token/netrc:
#        attic cache configure fleet --public
#   3. Capture the cache's public signing key and append it to
#      modules/common.nix nix.settings.extra-trusted-public-keys:
#        attic cache info fleet     # → the `fleet:...=` public key line
#   4. Mint a push token for the builder(s) and log them in (see common.nix).
{
  config = lib.mkIf config.mySecrets.enable {
    # RS256 JWT secret: EnvironmentFile with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
    # (generated `openssl genrsa -traditional 4096 | base64 -w0`). atticd signs and
    # validates all cache tokens with this key.
    age.secrets.atticd-server-token = {
      file = ../../secrets/atticd-server-token.age;
      # atticd runs as a DynamicUser; the module reads the EnvironmentFile as root
      # before dropping privileges, so root-readable (default 0400 owner root) is fine.
      mode = "400";
    };

    services.atticd = {
      enable = true;
      environmentFile = config.age.secrets.atticd-server-token.path;
      # monolithic: API server + GC + storage in one process (single-node fleet).
      mode = "monolithic";
      settings = {
        # Bind all interfaces; the firewall (below) restricts reachability to the
        # trusted mesh transports only — same trust model as wayvnc:5900 / asr:8762.
        listen = "[::]:8080";
        # Let the substituter serve directly (clients hit /<cache>/nar/...); keep
        # the default sqlite DB + local storage under the atticd StateDirectory.
      };
    };

    # Cache reachable ONLY over the Tailscale mesh (pull from anywhere) and the
    # direct Thunderbolt link (coordinator↔worker fast path) — never the LAN/wifi.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
    # thunderbolt0 is already a fully trusted interface (modules/strix.nix), so
    # 8080 is reachable there without an explicit per-port rule; listed here for
    # intent/documentation of the TB5 fast lane.
  };
}
