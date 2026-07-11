---
name: presentation-beta
description: Author HTML presentations the way the umbrella handbook deck was made — Claude writes reveal.js slide HTML directly against nix-vendored reveal 5.2.1 and the brand-kit hook; markdown files are speaker notes only, never the slide source. Use when the user says presentation, slides, deck, all-hands, speaker notes, reveal, rehearse, or "like the umbrella presentation". Prime directive — the deck is a self-contained snapshot dir (ALL assets local; the original umbrella deck's cdnjs hot-links are the anti-pattern); rehearse it from file:// in a bounded app window, and broadcast only via the publish-artifact skill.
when_to_use: new deck request; editing/restyling a deck; converting notes to slides; rehearsing; publishing a presentation for a meeting.
---

# presentation-beta — authored presentations

## Mental model (read first)

- **Claude authors the HTML directly** — full layout freedom per slide, like a claude.ai artifact. md→slides tools (marp, slidev) were evaluated and rejected; markdown constrains layout. The sibling `.md` file holds SPEAKER NOTES (umbrella pattern: per-slide notes + transitions), not slide source.
- **Scaffold, then write.** `artifact-deck-init <dir>` lays down vendored reveal + the brand-kit hook + a starter `index.html`; everything after that is authorship.
- **The brand kit is empty by ruling.** Style within reveal's stock theme + structural CSS; do not invent a bespoke visual identity per deck — tokens land in `tokens.css` at the very end, for all lanes at once.

## Live facts (verify before acting)

| Field | Value |
|---|---|
| Scaffold | `artifact-deck-init <dir>` (pkgs/artifact-deck; reveal 5.2.1 nix-vendored) |
| Rehearse (rung 0) | `artifact-view <dir>` — bounded app window from file:// |
| Brand kit hook | `assets/tokens.css` (copied from pkgs/artifact-render/tokens.css — EMPTY by ruling) |
| Publish | hand the dir to the publish-artifact skill (tailnet default; 1-day TTL for rehearsal shares) |
| Lineage | `skills/slides-skill/` corpus (superseded): umbrella-landbook.html + speaker-notes md |

## Workflow

```bash
artifact-deck-init ~/decks/q3-allhands      # scaffold
$EDITOR ~/decks/q3-allhands/index.html      # author slides (Claude writes these)
artifact-view ~/decks/q3-allhands           # rehearse, file://
# broadcast -> publish-artifact skill
```

## Hard rules

1. Never hot-link a CDN — every asset lives under `assets/`. The deck must pass the file:// test before it is done.
2. Speaker notes in a sibling `.md`, one `### Notes` block per slide with transitions (umbrella convention).
3. Diagrams get real design care (see the diagram-design reference in the old corpus notes) — no ASCII dumps on slides.
4. Don't restyle reveal per deck; brand goes in tokens.css when ruled.
5. Publishing and its TTL discipline belong to publish-artifact — this skill ends at a finished snapshot dir.
