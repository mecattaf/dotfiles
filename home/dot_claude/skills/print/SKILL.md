---
name: print
description: Render Markdown, plain text, or HTML into restrained, readable A4 PDFs with local fonts and headless Chrome, compare serif typography profiles, and submit validated documents to the Brother CUPS queue. Use when the user asks to print, typeset, make a paper copy, create an A4 PDF, compare print fonts, or turn Markdown into a document for physical reading.
---

# Print

## Autopilot rendering

**Auto-classification is retired as of 2026-08-29.** Typesetting decisions
used to come from the request-scoped NPU utility model; that NPU was
decommissioned permanently on both Strix Halo boxes and the `utility-model`
wrapper is no longer installed on any host. Nothing restores it.

`print-auto.py` still works and is still the fastest path to paper — the
retirement is deliberately non-fatal. It now renders with the deterministic
default that always backed the model (source-serif, duplex, no one-page
enforcement, kebab-case filename from the input stem), writes provenance
`"retired"` into decision.json, and prints one stderr notice saying so:

    ~/.claude/skills/print/scripts/print-auto.py INPUT.md \
      [--intent brief|document|form|specimen] [--print] \
      [--target-pages N] [--output-dir DIR]

Because nothing chooses typography for you any more, **use Manual rendering
below whenever the profile or layout actually matters** — anything literary,
formal, academic, or single-page. Reach for autopilot when the default is
fine and the job-directory bookkeeping is what you want. `--intent` is
accepted but no longer changes the outcome.

Every print becomes a dated job directory under ~/Paper/jobs (markdown
archived as source.md, rendered PDF, decision.json receipt recording npu /
npu-retry / fallback / retired provenance, plus pages_rendered /
target_pages / length_check).

**Render-verify-submit (issue #227) — MANDATORY when the user gave the
document an acceptance condition** (a page count, "one-pager", "N pages",
section/coverage requirements): pass `--target-pages N`. Every invocation
of `print-auto.py` always renders first and never submits in that same
step; `--print` only reaches CUPS afterward, and only if the rendered page
count matches `--target-pages` exactly. A mismatch prints nothing, writes
`length_check: "fail"` to decision.json, and exits 3 — revise the markdown
and re-run. This means the session can call `print-auto.py ... --print`
repeatedly while iterating toward the target and it is architecturally
impossible for a page to reach the printer before the render satisfies it.

**Never revise a document after `--print` has been passed.** If a
just-submitted job turns out short or wrong, `cancel <job>` is an
anti-pattern: by the time cancellation lands, pages are already out. Fix
the markdown, re-render (still without `--print`, and with `--force` to
overwrite the previous PDF), confirm the new render, and only then submit
— once. Do not treat a queued job as a draft.

**Quiet hours.** Between 00:00 and 06:00 physical printing sleeps:
--print still renders and validates, but the submission is spooled to
~/Paper/outbox and a persistent 06:05 timer flushes it to CUPS. When the
user says "print force" (or the situation genuinely demands paper at
night), pass **--force** to print immediately. Report honestly which
happened: submitted to CUPS now, or spooled for the morning flush.

## Manual rendering

Use the bundled script for deterministic local rendering:

    ~/.claude/skills/print/scripts/print-paper.py INPUT.md [options]

The pipeline is local:

    Markdown or HTML → print CSS → headless Chrome → A4 PDF → optional CUPS job

## Workflow

1. Confirm the requested content and output scope. Keep authored content outside
   the skill; this skill owns only rendering and submission.
2. Render before printing. The script checks that the requested font resolves
   instead of silently accepting a fallback, and checks A4 geometry when
   pdfinfo is available.
3. For a one-page request, pass **--require-one-page**. All variants render and
   validate before any of them is submitted.
4. Inspect the PDFs when layout judgment matters. Keep the generated HTML with
   **--keep-html** when diagnosing CSS or link behavior.
5. **When the user gave a length or completeness target that
   --require-one-page cannot express** (a stated page count, "make it N
   pages", "cover all of X"), render WITHOUT **--print** first, read the
   reported page count (or open the PDF), and only once it satisfies the
   target run:

       ~/.claude/skills/print/scripts/print-paper.py --submit-only RENDERED.pdf \
         [--sides one-sided|long-edge|short-edge] [--printer NAME]

   `--submit-only` never renders — it queues exactly the PDF path given, so
   the submit step cannot be the same act as an unverified render. Combining
   `--print` with the render in one call is reserved for outputs that are
   already fully self-validating in that same call (e.g.
   **--require-one-page**, which fails loudly before anything is queued).
   Do not combine an un-gated render with `--print` for anything else.
6. Pass **--print** only when the user explicitly asked for a physical print,
   and only after step 5's verification for any targeted document. Report the
   CUPS request IDs afterward.

## Typography profiles

| Profile | Face | Intended reading character |
|---|---|---|
| **garamond** | EB Garamond | literary, open, economical |
| **baskerville** | Libre Baskerville | crisp, formal, high contrast |
| **source-serif** | Source Serif 4 | contemporary editorial default |
| **times** | Liberation Serif | Times-compatible academic control |

Profiles use optical size and leading adjustments rather than forcing unlike
faces into one nominal metric. Page geometry remains constant: A4 portrait,
30 mm side margins, restrained black-on-white styling, widow/orphan control,
and no browser headers or footers.

Every page carries a bare 7 pt page number at the bottom right, set in the
reserved bottom margin through a CSS **@page** margin box. Chrome's own URL,
date, and title furniture stays disabled. The **--label** and **--compare**
profile caption shares that margin as a centered margin box, so it neither
overprints the last line of text nor reaches the page number.

Render all four comparison sheets:

    ~/.claude/skills/print/scripts/print-paper.py specimen.md \
      --compare --require-one-page --output-dir ./print-output

Render and physically print them:

    ~/.claude/skills/print/scripts/print-paper.py specimen.md \
      --compare --require-one-page --output-dir ./print-output --print

Render one ordinary document without a comparison label:

    ~/.claude/skills/print/scripts/print-paper.py document.md \
      --profile source-serif -o document.pdf

Use **--list-profiles** for the exact face, point size, and leading values.

## Printing boundary

- The default destination is **Brother_HL_L2445DW**; override it with
  **--printer** or PRINT_PAPER_PRINTER.
- Documents go through CUPS as already-rendered A4 PDFs. Do not use raw TCP
  9100 for formatted material; **brother-print-text** remains only for trivial
  plain text.
- Printing is duplex long-edge by default, which halves the paper a multi-page
  document costs. Pass **--sides one-sided** when the sheets must be single
  sided (posting, scanning, single-sided forms), or **--sides short-edge** for
  landscape-flip binding. A one-page job may carry the duplex option; it costs
  no extra sheet.
- Never add **--force** merely for convenience. Use it only when replacing the
  named generated files is intended.
- Do not claim physical completion from queue submission alone. Report that
  CUPS accepted the jobs; inspect queue state when the user asks for delivery
  confirmation.
- Submission is one-shot, not a draft. Never submit a rendered document you
  have not already verified against whatever the user asked for, and never
  follow a submission with `cancel` to revise — render again (Workflow §5,
  `--target-pages` for autopilot) and submit once (issue #227).

## Supported source

Markdown supports headings, paragraphs, emphasis, links, images, blockquotes,
ordered and unordered lists, fenced code, rules, and simple GFM tables. Relative
image paths resolve from the source file directory. HTML documents retain their
content and receive the print stylesheet as the final style block.

Lists follow CommonMark continuation rules, so repository Markdown written in
the house 80-column style prints as authored: a hard-wrapped line stays inside
its list item, nested items stay nested, and ordered numbering runs unbroken.
Never make an unwrapped print-only copy of a document to work around list
rendering.
