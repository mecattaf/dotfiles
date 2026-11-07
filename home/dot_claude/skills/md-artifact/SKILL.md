---
name: md-artifact
description: >-
  Render a Markdown document with artifact-render and view its self-contained snapshot with artifact-view. Use for md artifact, "render this markdown", "make this doc look nice", "open this doc in a window", or a readable page from a .md file. Supports GFM, math and Mermaid using local assets; output works from file:// without a server or network. To share a URL, use the external publish-artifact tool and skill.
---

# md-artifact — markdown docs as local-first artifacts

## Mental model (read first)

- **Render once, view anywhere.** `artifact-render` produces a snapshot dir (`index.html` + `assets/`) that is byte-identical when opened from `file://`, served privately through Tailscale Serve, or explicitly published through Cloudflare. If it needs a server or the network to look right, fix the snapshot before sharing it.
- **Viewing is not publishing.** The default terminal state is a bounded Chrome app window (`--app`, no tab bar — same mechanism as the PWA launchers in home.nix). No URL, no TTL, no debt. Publishing is a separate deliberate act via [[publish-artifact]].
- **Aesthetics are not yours to invent.** `house.css` is neutral-structural; the look comes from the brand kit `tokens.css`, which is DELIBERATELY EMPTY (Tom's ruling — tokens land at the very end). Do not hardcode colors/fonts into a doc to compensate.

## Live facts (verify before acting)

| Field | Value |
|---|---|
| Render | `artifact-render <doc.md> <outdir>` (pkgs/artifact-render; pandoc GFM, verified flag set) |
| View (rung 0) | `artifact-view <dir \| slug \| URL>` → `google-chrome --app` |
| Publishing | External `artifact-publish` tool and skill; Tailscale Serve privately, Cloudflare explicitly for public sharing |
| Brand kit hook | `pkgs/artifact-render/tokens.css` — EMPTY by ruling; imported last by both lanes |
| Mermaid | vendored IIFE 11.12.0, client-side, follows prefers-color-scheme |
| Scope | GFM + math (MathML) + mermaid. NO MDX (closed ruling 2026-07-11) |

## Verbs

```bash
artifact-render notes/foo.md /tmp/foo-artifact   # md -> snapshot dir
artifact-view /tmp/foo-artifact                  # bounded app window, file://
# want a URL? -> publish-artifact skill (tailnet default, TTL always)
```

Title = first `# h1` (else filename). Local images referenced by the doc must be copied into the snapshot dir manually — check for them.

On a host without a display, open the snapshot on the client or use
`artifact-publish` for a private HTTPS URL with an explicit TTL. The returned
Tailscale URL works without Caddy. `art.mecattaf.dev` is reserved for explicit
public sharing; do not construct a private URL from that domain.

## Hard rules

1. Snapshot must pass the file:// test — open it with `artifact-view <dir>` before calling it done; broken-at-rung-0 means broken everywhere.
2. No CDN links, no ESM script tags (CORS-blocked on file://), no absolute local paths in output.
3. Never edit `house.css` for a one-off look; brand belongs in `tokens.css` when Tom rules on it, per-doc hacks belong nowhere.
4. GFM only. MDX is a closed ruling — route app-shaped content to a static build + publish-artifact instead.
5. Rendering never requires the network or uploads content anywhere (this is why gh-markdown-preview was rejected as the render step — it posts the doc to GitHub's API; it remains fine as an interactive previewer).

## Reference paths

- Renderer + template + hook: `pkgs/artifact-render/` (this repo).
- Evidence for the tool choices: md-renderer-pick workflow 2026-07-11 (gh-markdown-preview = AJAX shell + API upload, CONFIRMED; pi-markdown-preview = no CLI, theme baked; both rejected as render step).
- Lineage: `skills/md-artifact-skill.md` corpus (deleted 2026-07-11 — its earlier viewer idea is superseded by the chrome --app bounded window; its two candidate repos were evaluated and rejected).
