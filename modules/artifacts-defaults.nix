# Artifact system identity/knobs — THE single edit point (Tom's modularity
# ruling 2026-07-11). Imported by BOTH the NixOS layer (modules/artifacts.nix,
# modules/caddy-artifacts.nix read it via the myArtifacts option defaults) and
# the package layer (overlays/default.nix passes values to pkgs/artifact-*),
# because an overlay cannot read NixOS `config`. Change the namespace/zone here
# and everything follows on the next rebuild: Caddy import dir, reaper sweep,
# artifact-view URL scheme, worker port range. The skills' live-facts tables
# point HERE as their verify-before-acting source — keep this file boring.
{
  # Cloudflare zone the namespace lives in (same CF account wrangler is
  # authenticated against — see secrets/wrangler-config.age, coordinator-only).
  zone = "mecattaf.dev";

  # Every artifact is <slug>.<namespace>. Stable across rungs (split-horizon):
  # tailnet rung = unproxied DNS record -> coordinator tailnet IP; public rung =
  # same name, proxied (Pages custom domain / tunnel). URL never changes.
  namespace = "art.mecattaf.dev";

  # The ONLY mutable surface of the whole system: <slug>.until-YYYYMMDD.caddy
  # site blocks + <slug>/ snapshot dirs. No side registry anywhere.
  stateDir = "/var/lib/artifacts";

  # "In doubt: 7 days." Never publish without a TTL — durable = git.
  defaultTtlDays = 7;

  # Worker tcp range (tailscale0 only) for publishing ports OUT of microVMs
  # (qemu user-net guests aren't tailnet-reachable; forward to worker:PORT and
  # hand that to publish-artifact). Bounded so the firewall stays auditable.
  livePortRange = {
    from = 8000;
    to = 8099;
  };
}
