---
name: publish-artifact
description: >-
  Publish an existing static snapshot publicly through Cloudflare only when Tom explicitly asks for public publication. Private artifact hosting was retired on 2026-11-08. Local viewing uses artifact-view and remains available. This skill does not render content or reactivate private Caddy, Tailscale Serve, the external publisher, or an artifact reaper.
---

# Public artifact publication

Private artifact hosting is retired (Tom, 2026-11-08). Do not publish a
private URL, restore the NAS artifact drop-dir, add Tailscale Serve handlers,
reinstall the private publisher's skill links, or restart its reaper.
A request to view locally uses `artifact-view <snapshot-dir>` on the client.
A request for a private URL requires a new explicit decision by Tom.

Explicit public publication remains a separate Cloudflare workflow. Verify
current Cloudflare documentation and the target account before using its CLI;
credentials stay on the NAS. Do not alter existing public projects or DNS as
part of private hosting retirement.

For an existing static snapshot, use Cloudflare Pages direct upload. The
namespace remains `art.mecattaf.dev` (zone `mecattaf.dev`), as recorded in
`modules/artifacts-defaults.nix`. Use a custom domain only when requested.
Every transient public publication needs a TTL (default seven days), an
unguessable slug unless Tom chooses one, and an explicitly owned teardown.
No local artifact reaper is installed. Durable static publication belongs in
a repository connected to Pages; a durable live service belongs in its own
declared deployment.

Retained public operations are inventory, publishing, expiry extension and
unpublishing on the explicitly selected Cloudflare project. Check actual
project/DNS ownership before changing or deleting anything. Never infer that
retiring private NAS hosting authorizes deleting a public Cloudflare project,
repository, or DNS record. Unexpose a live origin before destroying it.
