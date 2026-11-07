# Artifact system identity/knobs — THE single edit point (Tom's modularity
# ruling 2026-07-11). Imported by BOTH the NixOS layer (modules/artifacts.nix,
# modules/caddy-artifacts.nix read it via the myArtifacts option defaults) and
# the package layer (overlays/default.nix passes values to pkgs/artifact-*),
# because an overlay cannot read NixOS `config`. Change the namespace/zone here
# and everything follows on the next rebuild: Caddy import dir, reaper sweep,
# artifact-view URL scheme. The skills' live-facts tables
# point HERE as their verify-before-acting source — keep this file boring.
{
  # Cloudflare zone the namespace lives in (same CF account wrangler is
  # authenticated against — see secrets/wrangler-config.age, strix-only).
  zone = "mecattaf.dev";

  # Public publication namespace. New private artifacts use Tailscale Serve
  # URLs from the external artifact-publish utility, independently of this DNS.
  namespace = "art.mecattaf.dev";

  # Legacy Caddy drop-files and snapshots, retained until their expiry.
  # The external private publisher owns its own state independently.
  stateDir = "/var/lib/artifacts";

  # Default duration for legacy entries.
  defaultTtlDays = 7;
}
