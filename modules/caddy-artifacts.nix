{
  config,
  lib,
  pkgs,
  ...
}:
# Legacy artifact serving plane — NAS only (D48 moved here 2026-10-31).
# New private artifacts use the external artifact-publish utility and
# Tailscale Serve; public artifacts go through Cloudflare. Keep old drop-files
# reachable through their remaining TTL while their authors migrate.
#
#   /var/lib/artifacts/<slug>.until-YYYYMMDD.caddy   TTL in the FILENAME
#   /var/lib/artifacts/<slug>/                       static snapshot (if static)
#
# Legacy serving:
#   - .dev is HSTS-preloaded; HTTP-only drop-files fail in browsers (#678).
#     Do not create new private artifacts here. Tailscale Serve handles their
#     HTTPS independently of Caddy and public DNS.
#   - Public publication and its cleanup belong to the external Cloudflare
#     workflow. This legacy module does not provision a public tunnel.
#   - D48 sweeps legacy local files, then asks the independently installed
#     private publisher to expire its own Serve handlers and snapshots.
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
      auto_https disable_redirects
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

  # Ingress belongs to the host front door (hosts/nas/front-door.nix); this
  # module opens no port.

  systemd.services.artifact-reaper = {
    description = "Reap expired artifacts (legacy drop-dir and private Serve paths)";
    path = [
      pkgs.python3
      pkgs.tailscale
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe artifact-reaper;
      # Reuse D48's clock. The independently installed utility owns private
      # snapshot metadata and removes its exact Serve route before its files.
      ExecStartPost = "${pkgs.util-linux}/bin/runuser -u tom -- /home/tom/.local/bin/artifact-publish reap";
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
