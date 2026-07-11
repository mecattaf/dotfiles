{ config, lib, pkgs, ... }:
# Artifact serving plane — COORDINATOR only (fleet front door; Caddy is
# featherweight, so this honors the no-heavy-build doctrine; origins run on the
# worker). Realizes the publish-artifact skill's tailnet rung:
#
#   /var/lib/artifacts/<slug>.until-YYYYMMDD.caddy   TTL in the FILENAME
#   /var/lib/artifacts/<slug>/                       static snapshot (if static)
#
# Ephemerality lives ONLY here + CF metadata; everything else is declarative.
# v1 posture:
#   - auto_https off, plain HTTP :80 on the tailnet (WireGuard already encrypts
#     transport; off-tailnet resolvers get an unroutable 100.x). TLS via a
#     caddy-dns/cloudflare DNS-01 wildcard is the documented follow-up.
#   - PUBLIC live artifacts need the cloudflared tunnel back — re-minting that
#     credential is a DELIBERATE reversal of the 2026-07-05 removal (Tom ruled
#     2026-07-11 that publish-from-microvm stays available on Cloudflare too);
#     wire it as ONE static wildcard ingress *.<namespace> -> localhost Caddy
#     ("dumb pipe, smart Caddy") when the credential is minted.
#   - Reaper sweeps the LOCAL surface (drop-dir + snapshots). The CF-side sweep
#     (expired Pages projects, DNS records by comment) lands with the tunnel/API
#     wiring — until then, transient PUBLIC artifacts are torn down by hand per
#     the skill's Teardown section.
let
  cfg = config.myArtifacts;

  artifact-reaper = pkgs.writeShellApplication {
    name = "artifact-reaper";
    text = ''
      # Sweep expired artifacts: TTL is authoritative in the FILENAME
      # (<slug>.until-YYYYMMDD.caddy) — no side registry to consult or update.
      shopt -s nullglob
      today=$(date +%Y%m%d)
      changed=0
      for f in ${cfg.stateDir}/*.until-*.caddy; do
        base=$(basename "$f" .caddy)
        slug=''${base%%.until-*}
        exp=''${base##*.until-}
        [[ "$exp" =~ ^[0-9]{8}$ ]] || { echo "skip (bad stamp): $f"; continue; }
        if (( exp < today )); then
          echo "reap: $slug (expired $exp)"
          rm -f "$f"
          rm -rf "${cfg.stateDir}/''${slug:?}"
          changed=1
        fi
      done
      if (( changed )); then
        systemctl reload caddy
      fi
    '';
  };
in
{
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
    # The placeholder tmpfile below guarantees the glob always matches — Caddy
    # treats a zero-match import glob as a config error.
    extraConfig = ''
      import ${cfg.stateDir}/*.caddy
    '';
  };

  # tom owns the drop-dir (the agent publishes as tom; caddy only reads).
  systemd.tmpfiles.rules = [
    "d ${cfg.stateDir} 0755 tom users -"
    "f ${cfg.stateDir}/00-placeholder.caddy 0644 tom users -"
  ];

  # Tailnet-only ingress; nothing opens on LAN/WAN interfaces.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 ];

  systemd.services.artifact-reaper = {
    description = "Reap expired artifacts (drop-dir TTL sweep)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe artifact-reaper;
    };
  };
  systemd.timers.artifact-reaper = {
    description = "Daily artifact TTL sweep";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
