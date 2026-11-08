# Retained public artifact identity. Private Caddy/Tailscale hosting and its
# reaper were retired on 2026-11-08. These values install no serving plane.
{
  # Cloudflare zone the namespace lives in (same CF account wrangler is
  # authenticated against — see secrets/wrangler-config.age, strix-only).
  zone = "mecattaf.dev";

  # Optional custom-domain namespace for explicit public publication.
  # The LAN resolver no longer shadows these public names.
  namespace = "art.mecattaf.dev";

  # Legacy state location retained as metadata; no Caddy import, tmpfiles or
  # reaper is installed. Existing snapshots stay in place until disposed of.
  stateDir = "/var/lib/artifacts";

  # "In doubt: 7 days." Never publish without a TTL — durable = git.
  defaultTtlDays = 7;
}
