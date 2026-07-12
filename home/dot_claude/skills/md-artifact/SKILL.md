---
name: md-artifact
description: >-
  Render a markdown document into a self-contained artifact and view it in a bounded Chrome app window — the sovereign, local-first analogue of a claude.ai markdown artifact. Use when the user says md artifact, "render this markdown", "make this doc look nice", "open this doc in a window", artifact-render, artifact-view, or wants a readable/showable page from a .md file. GFM only (tables, task lists, footnotes, alerts, math, mermaid) — MDX was researched and ruled OUT 2026-07-11; never propose it. Prime directive — the output snapshot dir must render perfectly from file:// with zero server and zero network: local assets only, no CDN, mermaid is the vendored IIFE build. Viewing is rung 0 and incurs NO teardown debt; to give the doc a URL, chain the publish-artifact skill.
when_to_use: a .md needs rendering/viewing; "show me this doc"; doc looks wrong in the browser; mermaid diagram in markdown; preparing a doc that will later be published.
---

# md-artifact — markdown docs as local-first artifacts

## Mental model (read first)

- **Render once, view anywhere.** `artifact-render` produces a snapshot dir (`index.html` + `assets/`) that is byte-identical at every rung: opened from `file://` (rung 0), served by Caddy on the tailnet, or deployed to Cloudflare Pages. If it needs a server or the network to look right, it is broken — fix the snapshot, not the serving.
- **Viewing is not publishing.** The default terminal state is a bounded Chrome app window (`--app`, no tab bar — same mechanism as the PWA launchers in home.nix). No URL, no TTL, no debt. Publishing is a separate deliberate act via [[publish-artifact]].
- **Aesthetics are not yours to invent.** `house.css` is neutral-structural; the look comes from the brand kit `tokens.css`, which is DELIBERATELY EMPTY (Tom's ruling — tokens land at the very end). Do not hardcode colors/fonts into a doc to compensate.

## Live facts (verify before acting)

| Field | Value |
|---|---|
| Render | `artifact-render <doc.md> <outdir>` (pkgs/artifact-render; pandoc GFM, verified flag set) |
| View (rung 0) | `artifact-view <dir \| slug \| URL>` → `google-chrome --app` |
| Config edit point | `modules/artifacts-defaults.nix` (namespace `art.mecattaf.dev`, TTL, stateDir) |
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

## Hard rules

1. Snapshot must pass the file:// test — open it with `artifact-view <dir>` before calling it done; broken-at-rung-0 means broken everywhere.
2. No CDN links, no ESM script tags (CORS-blocked on file://), no absolute local paths in output.
3. Never edit `house.css` for a one-off look; brand belongs in `tokens.css` when Tom rules on it, per-doc hacks belong nowhere.
4. GFM only. MDX is a closed ruling — route app-shaped content to a static build + publish-artifact instead.
5. Rendering never requires the network or uploads content anywhere (this is why gh-markdown-preview was rejected as the render step — it posts the doc to GitHub's API; it remains fine as an interactive previewer).

## Reference paths

- Renderer + template + hook: `pkgs/artifact-render/` (this repo).
- Evidence for the tool choices: md-renderer-pick workflow 2026-07-11 (gh-markdown-preview = AJAX shell + API upload, CONFIRMED; pi-markdown-preview = no CLI, theme baked; both rejected as render step).
- Lineage: `skills/md-artifact-skill.md` corpus (deleted 2026-07-11 — its quickshellX-viewer idea is superseded by the chrome --app bounded window; its two candidate repos were evaluated and rejected).
