---
name: effective-html
description: Build a self-contained HTML artifact — report, explainer, comparison, deck, prototype, plan page, or a full-screen architecture/stack diagram page — in the "effective HTML" style, matching a bundled example corpus for density and tone. Use when the user asks for effective HTML, a single self-contained HTML file/artifact/report/explainer/plan/diagram page, or an HTML output that should look like polished hand-rolled HTML rather than a framework app.
---

# Effective HTML

<!-- Vendored from plannotator/backnotprop effective-html plugin, bundling Thariq Shihipar's html-effectiveness corpus. -->

Router skill. Every mode produces a single self-contained HTML file and always includes
dark mode (hand-rolled CSS variables on `:root` / `html.dark`, a theme toggle button,
`localStorage` persistence, and an apply-before-paint script in `<head>` defaulting to
`prefers-color-scheme`).

**Before writing anything, review the shared example corpus at
[`references/html-effectiveness/`](references/html-effectiveness/) and the mode's SKILL.md,
then imitate the corpus's style, density, and tone.** The corpus is the taste reference —
match it rather than inventing a look.

## Modes

- **html** — general self-contained HTML artifact (report, explainer, comparison, deck,
  prototype — anything that isn't specifically a diagram or a plan). Load
  [`references/html/SKILL.md`](references/html/SKILL.md).

- **html-diagram** — full-screen, SVG-first architecture / stack diagram pages, light on
  prose, sometimes interactive/animated. Load
  [`references/html-diagram/SKILL.md`](references/html-diagram/SKILL.md) (it also cites a
  finished example, `references/html-diagram/references/architecture-example.html`).

- **html-plan** — pragmatic, visually organized plan pages that keep the user's own
  wording and just clean up the grammar/structure. Load
  [`references/html-plan/SKILL.md`](references/html-plan/SKILL.md).

Pick the mode that fits the request, load its SKILL.md and the corpus, then write.
