---
name: print
description: Put a Markdown document or an existing PDF on paper by dropping it into ${paper_root}/intake/ on nas; paper-daemon renders Markdown on compute (a PDF is printed as it is), validates, prints during working hours and writes a receipt from the printer itself. Use when the user asks to print, make a paper copy, print a PDF such as an invoice or a form, or turn Markdown into a document for physical reading.
---

# Print

`/print` is one file write. You do not render, submit, read queues, or
decide when printing happens: paper-daemon on **nas** owns all of it
(dotfiles#384).

## The whole contract

Resolve `paper_root=$(utility-path paper)` on **nas**. From another host,
resolve it with `ssh nas utility-path paper`. Use that returned root below;
the concrete storage location is a private host setting.

Write the Markdown to a hidden temporary name, then rename it into place,
on **nas**, the canonical home and queue owner:

    ${paper_root}/intake/.<slug>.md.tmp   →   ${paper_root}/intake/<slug>.md

`<slug>` is a short kebab-case name for the document. The rename is what
starts the job, so never write straight to `<slug>.md`. From another host,
copy it over first (`scp FILE nas:${paper_root}/intake/.<slug>.md.tmp`,
then `ssh nas mv ${paper_root}/intake/.<slug>.md.tmp ${paper_root}/intake/<slug>.md`).
When already on nas, write and rename locally. Never drop on compute.
Markdown drops contain their own text. Local image files are not copied to
compute and network images are not fetched: embed image data or drop an
existing PDF instead.

Optional front matter, only when the user asked for it:

    ---
    target_pages: 10        # the user gave a page count ("one-pager" = 1)
    page_slack: 0           # only for "exactly N" or a one-pager; default 2
    sides: one-sided        # one-sided | duplex (default) | short-edge
    profile: garamond       # garamond | baskerville | source-serif | times
    force: true             # "print force": print now even 00:00–06:00
    ---

Any `target_pages: N` passes when the render is N−2 to N+2 pages (the
default `page_slack` of 2, for every N). Do not trim or pad to hit N exactly.
Set `page_slack: 0` only for a one-pager or when the user said "exactly".

Leave typography to the daemon unless the user named a face or layout.
Never set `force` for convenience.
The local tool asks Gufo's Qwen Flash model for typesetting choices. WeasyPrint
produces the PDF on strix-coordinator. The daemon tries up to three measured
layouts when the PDF is too long. It preserves the Markdown exactly, keeps
body type at least 10 pt, and rejects a remaining page-count miss.

## An existing PDF

An invoice, a receipt or a form that already exists as a PDF is dropped the
same way and printed as it is:

    ${paper_root}/intake/.<slug>.pdf.tmp   →   ${paper_root}/intake/<slug>.pdf

Never rasterize a PDF, embed it as an image, or transcribe it into Markdown
to get it printed: the user wants the original document. The daemon reads
the page count from the file, so `target_pages` does not apply. A malformed
or encrypted PDF is rejected. Pages that are not A4 (a Letter invoice) are
scaled to fit A4, and the receipt says `fit_to_page: true`.

By default a 1 or 2 page PDF prints one-sided and a longer one duplex. Only
when the user asked for something else, write a sidecar **before** the
rename, `${paper_root}/intake/<slug>.pdf.json`:

    {"sides": "duplex", "force": true}

`sides` is one-sided, duplex or short-edge; `force` follows the rule above.
Nothing else is accepted there.

## Where the outcome appears

Everything lands in `${paper_root}/<state>/<slug>/` (a repeated slug gets a
timestamp suffix):

| directory | meaning |
|---|---|
| `printed/<slug>/receipt.json` | paper is out: the printer reported the job completed with `impressions_completed` equal to the rendered pages (for a PDF, its own pages) |
| `outbox/<slug>/` | it is 00:00–06:00; it prints at 06:05 |
| `rejected/<slug>/reason.json` | the render fell outside `target_pages` ± `page_slack`, the front matter or sidecar was invalid, or the PDF was malformed or encrypted; nothing was printed. Revise and drop again |
| `failed/<slug>/failure.json` | something went wrong at the queue or the printer; the evidence is beside it and paper-daemon.service is left failed for the fleet's failure markers |

Report to the user what the directory says, and only that. A drop with no
directory yet is still being rendered or printed; wait, do not re-drop. Do
not claim paper without `receipt.json`.

## Not this skill

`${paper_root}/inbox/` is the Huion notepad's, not a print drop. Rendering a PDF
without printing, or comparing typefaces, uses the renderer by hand:
`~/.claude/skills/print/scripts/README.md`.
