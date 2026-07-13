---
name: resume-builder
description: Regenerate Tom's resume PDF from constrained markdown with the `resume-pdf` CLI (installed in ~/.local/bin; fonts in ~/.local/share/resume-builder). Preserves the exact look of Tom's original hand-maintained docx resume — Garamond, small-caps ruled section heads, right-aligned dates — with pixel-level metrics extracted from the docx internals. Use when tailoring, editing, rebuilding, or exporting Tom's resume/CV to PDF; when the user mentions resume-pdf, resume-builder, "rebuild my resume", "tailor my resume for X", or edits files like *-resume.md in notes/references/personal/resumes-essays/. Content lives in the notes repo; this skill owns only the format and the build.
when_to_use: Any resume/CV regeneration or tailoring for Tom; edits to resumes-essays/*.md that need a PDF; questions about the resume markdown grammar or why the PDF looks off.
---

# resume-builder — Tom's resume, markdown → PDF at docx parity

One command, no dependencies beyond Chrome:

```
resume-pdf <resume>.md [-o out.pdf] [--keep-html]
```

Works from any cwd. Default output: input path with `.pdf`. `--keep-html`
keeps the intermediate HTML next to the PDF for debugging.

Canonical content (as of 2026-07-13):
`~/mecattaf/notes/references/personal/resumes-essays/2026-cognition-resume.md`.
Layout parity reference (old content, right look):
`~/mecattaf/notes/references/personal/resumes-essays/Thomas Mecattaf Resume 2021.pdf`.

**Division of labor: this skill owns the FORMAT; the notes repo owns the
CONTENT.** Tailoring a resume = editing the markdown, never the CSS.

## Markdown grammar (constrained — the parser is dumb on purpose)

```markdown
# THOMAS MECATTAF                                  ← name, centered small-caps

line | line | [LinkedIn](url)                      ← contact, first plain line;
                                                     pipes render bold 11pt,
                                                     digit ordinals (87th) get
                                                     auto-superscripted

## EDUCATION                                       ← ruled section heading

**Company,** City — Sep 2016 – May 2020            ← entry header; date after the
                                                     LAST " — " goes flush right
*Role line*                                        ← italic via the asterisks
*Role* — Jun 2020 – Jul 2021 (full-time)           ← role with right date;
                                                     trailing (...) renders 10pt
- bullet text with **bold**, *italic*, __underline__, [links](url)
  - two-space indent = level-2 bullet
```

Rules the parser enforces / assumes:

- The date separator is exactly `space + em dash + space` (` — `), split on the
  **last** occurrence. Em dashes *inside* bullet text are safe (bullets are
  never date-split). An entry-header or role line whose text contains ` — `
  but has no date will mis-split — rephrase or use a hyphen there.
- Blank lines separate entries (they become the 12.375pt gap). No blank line
  between a `##` heading and its first entry.
- HTML comments `<!-- ... -->` are stripped — use them freely for draft notes
  and confirm-before-sending flags, on their own line or trailing a line. A
  comment-only line does NOT count as a blank line (it won't split an entry).
- Lines starting `**` = entry header; starting `*` = role line; `- ` = bullet;
  anything else = plain paragraph. There is no other structure.
- A trailing parenthetical in a *date* (e.g. `(part-time)`) automatically
  drops to 10pt, matching the original.

## Verify after every build (checklist)

1. Read the output PDF (the Read tool renders it) and check: name/contact
   centered; every section head has its rule; every date flush right; italics
   only where the markdown put them; bullets aligned with a hanging indent.
2. Check page count — visible from step 1's Read output (one block per page).
   The format is content-driven; if an edit pushes a section awkwardly across
   a page break, tighten content, don't touch the CSS.
3. If you added or changed any link, rebuild with `--keep-html` and check the
   `href="..."` values are byte-identical to the URLs in the markdown — a
   wrong href is invisible in the rendered PDF.

## Invariants (why the numbers are what they are — do not "clean up")

All metrics were extracted from the internals of the original
`Thomas Mecattaf Resume.docx` (retired 2026-07-13; never regenerate from it):

- US Letter, margins 0.5in top/left/right, 0.4in bottom
- Garamond (Google Docs' EB Garamond) — the TTFs in
  `~/.local/share/resume-builder/fonts/` are the ones that were embedded in
  the docx itself, plus Noto Sans Symbols for the ● bullet glyph
- Body 11pt, name 15pt bold small-caps, section heads 12pt bold small-caps
  with a 0.75pt black rule (1pt below the text)
- **Line-height 1.125** = Word "single" spacing for this font (from its hhea
  table). The make-or-break parity number — do not round it.
- Entry gap = one blank 11pt line = 12.375pt (`--gap` in the CSS)
- Bullets: 0.25in hanging indent; level 2 at 0.75in with a Courier "o"
- Links #0563c1 underlined; dates right-aligned
- The PDF **text layer must stay in reading order** (entry header, then its
  bullets) because ATS resume parsers read raw extracted text. Positioned and
  floated elements break this in Chrome's PDF export — that's why bullets are
  in-flow hanging indents and must never become `position:`/`float:` styles.

All styling lives in the `CSS` constant at the top of `resume-pdf`
(repo: `dotfiles/home/dot_local/bin/resume-pdf`). If Tom asks for a format
change, edit there, rebuild, and diff against a previous PDF so the change is
the only visible difference.
