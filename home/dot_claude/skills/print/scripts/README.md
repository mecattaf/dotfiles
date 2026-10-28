# Print renderer (manual use)

Physical printing is not done from here. It is one drop into
`~/Paper/intake/` on **nas** (see `../SKILL.md`), and paper-daemon (`pkgs/paper-daemon`)
is the only submitter: it sends Markdown to `paper-render` on compute, checks the queue,
submits, and writes the receipt from the printer. These scripts are the
renderer it uses, documented for the two things an agent may still do by
hand: make a PDF without printing, and compare typefaces.

## print-auto.py — the daemon's render step

    print-auto.py INPUT.md [--intent brief|document|form|specimen] \
      [--target-pages N] [--page-slack N] [--profile P] [--sides one-sided|duplex] [--output-dir DIR]

The request-scoped utility model (`utility-model` bundled with `paper-render`, which
forwards to Gufo at `http://strix-coordinator:8731`) picks profile, one-page
enforcement, duplex, filename and title; `--profile`/`--sides` override it.
Classification failure is non-fatal: one stderr line, the deterministic
default (source-serif, duplex, no one-page enforcement), provenance
`"fallback"`. The job directory (default `~/Paper/jobs/<date>-print-<slug>-<time>`)
gets `source.md`, the PDF and `decision.json` (`pages_rendered`,
`target_pages`, `page_slack`, `length_check`, `render_attempts`, `layout`). A render more than
`--page-slack` pages (default 2) from `--target-pages` exits 3. It has
no `--print`: nothing here reaches CUPS.

An overlong render gets at most two further measured attempts (`compact`, then
`dense`). The original Markdown stays unchanged. Type never goes below 10 pt;
the narrowest margins are 23 mm at the sides and 17/18 mm top/bottom. Short
sources are rejected without padding. `paper-render` packages Chromium, the
four font families, pdfinfo and the Gufo `utility-model` wrapper, so rendering
does not depend on an interactive desktop or inherited PATH. The NAS checks
the returned PDF itself before it reaches CUPS; compute returns no receipt.

## print-paper.py — the renderer

    print-paper.py INPUT.md [--profile P] [-o OUT.pdf | --output-dir DIR] \
      [--compare] [--label] [--require-one-page] [--keep-html] [--force] \
      [--layout standard|compact|dense]

Markdown or HTML → print CSS → headless Chrome → A4 PDF. The script checks
that the requested font resolves instead of silently accepting a fallback,
and checks A4 geometry when pdfinfo is available. `--require-one-page` fails
loudly if any output is not exactly one page. `--keep-html` keeps the
generated HTML for diagnosing CSS or links.

Its `--print`/`--submit-only` flags still exist for Tom at a terminal. They
trust `lp`'s exit code and write no receipt, which is exactly what #384
retired for agents; an agent uses the drop.

### Typography profiles

| Profile | Face | Intended reading character |
|---|---|---|
| **garamond** | EB Garamond | literary, open, economical |
| **baskerville** | Libre Baskerville | crisp, formal, high contrast |
| **source-serif** | Source Serif 4 | contemporary editorial default |
| **times** | Liberation Serif | Times-compatible academic control |

Profiles use optical size and leading adjustments rather than forcing unlike
faces into one nominal metric. Default page geometry is A4 portrait,
30 mm side margins, restrained black-on-white styling, widow/orphan control,
and no browser headers or footers.

Every page carries a bare 7 pt page number at the bottom right, set in the
reserved bottom margin through a CSS `@page` margin box. `--label` and
`--compare` add a centered profile caption in the same margin, clear of the
last line of text and of the page number.

Render all four comparison sheets (no printing):

    print-paper.py specimen.md --compare --require-one-page --output-dir ./print-output

`--list-profiles` prints the exact face, point size and leading values.

### Sides

Printing is duplex long-edge by default, which halves the paper a multi-page
document costs. `one-sided` is for sheets that will be posted, scanned or
filled in; `short-edge` for landscape-flip binding. In a drop these are the
`sides:` front-matter key (`duplex` means long-edge).

### Supported source

Markdown supports headings, paragraphs, emphasis, links, images, blockquotes,
ordered and unordered lists, fenced code, rules, and simple GFM tables; a
leading `---` front-matter block is stripped. In a manual local render, relative
image paths resolve from the source file directory. The NAS drop sends only
Markdown to compute, so local image references are rejected; drop an existing
PDF for a document with local assets. HTML documents keep their content and get
the print stylesheet as the final style block.

Lists follow CommonMark continuation rules, so repository Markdown written in
the house 80-column style prints as authored: a hard-wrapped line stays inside
its list item, nested items stay nested, and ordered numbering runs unbroken.
Never make an unwrapped print-only copy of a document to work around list
rendering.

Raw TCP 9100 (`brother-print-text`) remains a terminal-only escape hatch for
trivial plain text. Agents always use the drop and the printer receipt.
