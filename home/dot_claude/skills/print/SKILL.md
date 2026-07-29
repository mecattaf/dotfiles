---
name: print
description: Render Markdown, plain text, or HTML into restrained, readable A4 PDFs with local fonts and headless Chrome, compare serif typography profiles, and submit validated documents to the Brother CUPS queue. Use when the user asks to print, typeset, make a paper copy, create an A4 PDF, compare print fonts, or turn Markdown into a document for physical reading.
---

# Print

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
5. Pass **--print** only when the user explicitly asked for a physical print.
   Report the CUPS request IDs afterward.

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
- Default to one-sided output. Use **--sides long-edge** only when duplex was
  requested or clearly suits a multi-page document.
- Never add **--force** merely for convenience. Use it only when replacing the
  named generated files is intended.
- Do not claim physical completion from queue submission alone. Report that
  CUPS accepted the jobs; inspect queue state when the user asks for delivery
  confirmation.

## Supported source

Markdown supports headings, paragraphs, emphasis, links, images, blockquotes,
ordered and unordered lists, fenced code, rules, and simple GFM tables. Relative
image paths resolve from the source file directory. HTML documents retain their
content and receive the print stylesheet as the final style block.
