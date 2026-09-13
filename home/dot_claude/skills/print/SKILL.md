---
name: print
description: Put a Markdown document on paper by dropping it into ~/Paper/intake/ on the coordinator; paper-daemon renders, validates, prints during working hours and writes a receipt from the printer itself. Use when the user asks to print, make a paper copy, or turn Markdown into a document for physical reading.
---

# Print

`/print` is one file write. You do not render, submit, read queues, or
decide when printing happens: paper-daemon on the coordinator owns all of it
(dotfiles#384).

## The whole contract

Write the Markdown to a hidden temporary name, then rename it into place,
on the **coordinator**:

    ~/Paper/intake/.<slug>.md.tmp   →   ~/Paper/intake/<slug>.md

`<slug>` is a short kebab-case name for the document. The rename is what
starts the job, so never write straight to `<slug>.md`. From another host,
copy it over first (`scp FILE coordinator:~/Paper/intake/.<slug>.md.tmp`,
then `ssh coordinator mv ~/Paper/intake/.<slug>.md.tmp ~/Paper/intake/<slug>.md`).

Optional front matter, only when the user asked for it:

    ---
    target_pages: 10        # the user gave a page count ("one-pager" = 1)
    sides: one-sided        # one-sided | duplex (default) | short-edge
    profile: garamond       # garamond | baskerville | source-serif | times
    force: true             # "print force": print now even 00:00–06:00
    ---

Leave typography to the daemon unless the user named a face or layout.
Never set `force` for convenience.

## Where the outcome appears

Everything lands in `~/Paper/<state>/<slug>/` (a repeated slug gets a
timestamp suffix):

| directory | meaning |
|---|---|
| `printed/<slug>/receipt.json` | paper is out: the printer reported the job completed with `impressions_completed` equal to the rendered pages |
| `outbox/<slug>/` | it is 00:00–06:00; it prints at 06:05 |
| `rejected/<slug>/reason.json` | the render did not match `target_pages` (or the front matter was invalid); nothing was printed. Revise and drop again |
| `failed/<slug>/failure.json` | something went wrong at the queue or the printer; the evidence is beside it and the client got a notification |

Report to the user what the directory says, and only that. A drop with no
directory yet is still being rendered or printed; wait, do not re-drop. Do
not claim paper without `receipt.json`.

## Not this skill

`~/Paper/inbox/` is the Huion notepad's, not a print drop. Rendering a PDF
without printing, or comparing typefaces, uses the renderer by hand:
`~/.claude/skills/print/scripts/README.md`.
