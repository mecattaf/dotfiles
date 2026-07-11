---
name: publish-artifact
description: Sovereign replacement for claude.ai Artifacts — give any artifact a URL under art.mecattaf.dev; tailnet-private by default, public via Cloudflare on request, ALWAYS with a TTL. Inputs are ONLY a static snapshot dir or a live host:port — this skill is rendering-blind (docs come from md-artifact, decks from presentation-beta, apps from their own builds). Use when the user says publish, share, expose, broadcast, demo, "give me a URL", "show me on my phone", art.mecattaf.dev, Pages, tunnel, "put this up for a week", bump, unpublish, or wants content reachable beyond localhost. Supersedes the built-in claude.ai Artifact tool for Tom's content unless he explicitly asks for claude.ai hosting. Prime directive — every publish incurs a TTL'd teardown debt; "indefinite" is not a TTL value: durable static graduates to a GitHub repo + Pages git integration, durable live gets declared in nix. If the goal is only LOCAL viewing, stop — that is rung 0 (artifact-view), no publish needed.
when_to_use: something rendered/built/running needs a URL; sharing with a device or person; extending (bump) or revoking an exposure; a leaked drop-dir entry or expired Pages project; deciding tailnet vs public vs graduation.
---

# publish-artifact — the sovereign artifact ladder

## Mental model (read first)

- **Rendering-blind.** An artifact is a snapshot dir or a `host:port`. Never ask where it came from; never render here. The microvm is the workshop, not the gallery — static content NEVER holds a VM alive.
- **Stable URL across rungs.** `<slug>.art.mecattaf.dev` is minted at first publish and survives promotion (split-horizon DNS: tailnet rung = unproxied record → coordinator tailnet IP, unroutable off-tailnet; public rung = same name, proxied).
- **Rung 0 exists and is free.** `artifact-view <dir>` (bounded app window from file://) needs nothing from this skill. Publish only to cross a device/person boundary.
- **Ephemerality lives in ONE place:** the drop-dir (TTL in the FILENAME) plus CF metadata (expiry in the DNS comment / project name). No side registry, ever.

## Live facts (verify before acting)

| Field | Value |
|---|---|
| Config edit point | `modules/artifacts-defaults.nix` — namespace `art.mecattaf.dev`, zone `mecattaf.dev`, stateDir, TTL 7d, port range |
| Publish host | coordinator ONLY (gh + wrangler creds live there — operator-box ruling, secrets.nix) |
| Drop-dir | `/var/lib/artifacts/` — `<slug>.until-YYYYMMDD.caddy` + `<slug>/` snapshot; owned by tom, read by caddy |
| Reaper | `artifact-reaper.timer` daily on coordinator — LOCAL sweep only for now; CF-side sweep pending API wiring |
| Tailnet serving | Caddy :80 on tailscale0, plain HTTP v1 (TLS via caddy-dns/cloudflare DNS-01 = pending follow-up) |
| Public live | PENDING: cloudflared tunnel credential must be re-minted (deliberate reversal of the 2026-07-05 removal, ruled 2026-07-11) — one static wildcard ingress `*.art.mecattaf.dev` → localhost Caddy |
| Live origins | worker ports 8000–8099 (open on tailscale0; see microvm skill "publishing a port out of a VM") |
| Inventory | `wrangler pages project list --json` (Git Provider column: git-integrated = durable, direct-upload = transient) + `ls /var/lib/artifacts/` |

## Path decision — pick before you publish

```
Only local viewing needed?  → STOP: artifact-view <dir>. No debt.
STATIC (snapshot dir) → audience?
  Tom's devices → TAILNET: drop a file_server block, TTL
  others        → PUBLIC: wrangler pages deploy, TTL, UNGUESSABLE slug
                  unless Tom says otherwise (the capability URL is the password)
  forever       → GRADUATE: gh repo create + Pages git integration.
                  Exits this skill; per-repo doctrine takes over.
LIVE (host:port) → origin must outlive the TTL (⇒ durable `microvm -c` on the
                   worker — never a foreground ephemeral VM). Audience?
  tailnet → drop a reverse_proxy block, TTL
  public  → NEEDS the tunnel (see Live facts: pending credential)
  forever → declare a service in nix. Exits this skill.
```

In doubt: tailnet, 7 days, human slug.

## Verbs (run on the coordinator)

### Publish static to tailnet

```bash
slug=my-doc; until=$(date -d "+7 days" +%Y%m%d)
cp -r /path/to/snapshot "/var/lib/artifacts/$slug"
cat > "/var/lib/artifacts/$slug.until-$until.caddy" <<EOF
http://$slug.art.mecattaf.dev:80 {
	root * /var/lib/artifacts/$slug
	file_server
}
EOF
sudo systemctl reload caddy
# DNS (once per slug): unproxied A record -> coordinator tailnet IP, comment "artifact expires=$until"
```

### Publish live origin to tailnet

Same drop-file with `reverse_proxy worker:PORT` instead of root/file_server.

### Publish static public (Pages)

```bash
wrangler pages project create "$slug" --production-branch main
wrangler pages deploy /path/to/snapshot --project-name "$slug" --branch main \
  --commit-dirty --commit-message "expires=$until"
# custom domain + DNS flip via CF API (curl, CLOUDFLARE_API_TOKEN) if the stable URL is wanted
```

### List / bump / unpublish

```bash
ls -1 /var/lib/artifacts/*.caddy; wrangler pages project list --json   # inventory
mv "$slug.until-OLD.caddy" "$slug.until-NEW.caddy" && sudo systemctl reload caddy   # bump
# unpublish (FULL teardown, in order):
rm -f "/var/lib/artifacts/$slug".until-*.caddy && rm -rf "/var/lib/artifacts/${slug:?}"
sudo systemctl reload caddy
wrangler pages project delete "$slug" --yes 2>/dev/null || true   # if it went public
# + delete the slug's DNS record (CF API). Reaper is the BACKSTOP, not the mechanism.
```

### Graduate (durable static)

`gh repo create` + push the source → connect CF Pages git integration → keep the slug's DNS as the custom domain → unpublish the transient copy. The artifact is now a repo; per-repo doctrine applies.

## Hard rules

1. Every publish gets a TTL; default 7 days. "Indefinite" = git (repo or nix), never a long TTL.
2. Publish only from the coordinator (credential doctrine).
3. Unexpose BEFORE destroying a live origin — microvm destroy step 0 points here.
4. Exposure TTL ≤ origin lifetime; public+live ⇒ durable microvm path.
5. Transient public artifacts get unguessable slugs; human slugs are for tailnet or graduated things.
6. Drop-dir filenames + CF metadata are the ONLY state. Never a side registry.
7. This skill is the DEFAULT over the claude.ai Artifact tool; claude.ai hosting only on explicit request.
8. Until the CF-side reaper lands, every public publish is finished only when its teardown is either scheduled (TTL respected by hand) or done.

## Reference paths

- Serving plane + reaper: `modules/caddy-artifacts.nix`; knobs: `modules/artifacts-defaults.nix`.
- Authoring lanes: [[md-artifact]] (docs), [[presentation-beta]] (decks); origin seam: [[microvm]].
- Evidence base: md-renderer-pick workflow + wrangler-inventory findings, 2026-07-11 (wrangler `--json` emits display rows — absolute timestamps need the CF API; live production deployments can't be deleted without deleting the project, which is exactly what transient reaping does).
