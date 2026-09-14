# Personal handwriting OCR workbench

Started 2026-09-14. Six distinct page families from 13 JSON captures, with
independent Codex and Claude readings. This is a calibration and review set;
there is no measured OCR accuracy or writer-confirmed ground truth yet.

Subsequent experiments: [live Halogen audit](runs/halogen-vanilla-2026-09-14/AUDIT.md),
[vanilla comparison](runs/halogen-vanilla-2026-09-14/COMPARISON.md), and
[prompt caching / compilation / escalation notes](OPTIMIZATION-NOTES.md).
The benchmark keeps original raw answers and provisional references separate.
The consolidated [thinking-level and unified-memory benchmark](BENCHMARK.md)
includes measured resident footprint and an additional large-image probe.
The [context-resolution prototype](CONTEXT-RESOLUTION.md) adds provenance-backed
vocabulary retrieval for hard spans, inspired by the voice-mode investigation.

Start with [LOOKUP.md](LOOKUP.md) for 12 candidate word examples, or
[REVIEW.md](REVIEW.md) for the page transcription crops. Corrections belong in
`corpus.json` (transcript regions) and `lookup.json` (word examples): set
`confirmed_text` to the literal text and `label_status` to `confirmed` only
after Tom confirms that entry. Keep the candidate and original evidence.
Corrections to a whole line do not automatically confirm every word crop.

## Files and reproduction

- `corpus.json`: source paths, region coordinates, provisional Codex readings,
  review notes, and empty confirmation fields.
- `lookup.json`: candidate word labels, crop coordinates, and confirmation fields.
- `manifest.json`: SHA-256 of original JSON bytes and canonical stroke content,
  exact duplicates and earlier prefix captures grouped by page family.
- `crops/`: full-page and local PNG renders directly from stroke JSON. Coordinates
  follow the extractor's 900 × 1190 canvas with 15 px padding. Full pages render
  at 2×; crops at 3×; width is 1.2 page pixels. Pressure is retained in source
  JSON, but this baseline renders constant-width strokes. It synthesizes no ink.
- `runs/codex-initial.json`: blind full-page Codex candidates before comparison.
- `runs/claude-independent.json`: complete CLI result, model usage and metadata.
- `runs/claude-transcription.json`: extracted independent Claude transcription.
- `HALOGEN.md`: local API findings and the proposed evaluation protocol.

Regenerate derived files with `python3 /home/tom/huion/ocr/prepare.py` (Pillow
required). This overwrites the manifest, Markdown review/lookup and generated
images, leaving labels and original captures intact. Old generated crops can
remain after a region is renamed; only current JSON and Markdown define the set.
The roots are local absolute paths; update them when moving this workbench.

Some adjoining lines have overlapping ascenders and descenders. Use the full
page when a crop includes neighboring ink. The p03 block stays together to
preserve its six physical lines and avoid clipping them into false letters.

## First comparison

The readings broadly agree on the sentences, but agreement is not proof.

| Location | Main unresolved issue |
| --- | --- |
| p01 first line | `light` is the leading reading; writer confirmation pending |
| p01 gel ink line | literal `unironically` versus an apparently omitted i, and final punctuation |
| p01 circle label | `Reminder`, `Remainder`, or `Remaider`; keep the circle as a separate mark |
| p01 last line | `Okay` / `OKay`; enlargement supports a capital K |
| p03 device name | visual `Huyon` versus expected `Huion`; do not substitute the known brand automatically |
| p04/p05 second lines | both readers propose `has been done`; joined strokes remain ambiguous |
| p05 first line | Codex `now`, Claude `new`; initial case of Test also differs |
| p05 final mark | exclamation versus comma/other mark |
| p06 | separate c-shaped mark before `written`; do not silently remove it |

Claude speculated about dropped strokes on p06. That is unverified. A comparison
with the paper original is needed before attributing odd shapes to capture loss.

## How this becomes a useful lookup table

Use confirmed words and short joins as visual examples. An alphabet alone loses
the context of connected handwriting. The present candidates expose recurring
`writing`, `th`, descenders, and `now`/`new`. They do not establish deterministic
substitutions such as “this shape always means g.” Add multiple confirmed examples
from ordinary notes, including genuine spelling errors, names and abbreviations.

Keep literal transcription separate from any cleaned reading. Preserve spelling,
case, line breaks, numbers, crossed-out material, bullets and uncertainty. Treat
word spacing as a transcription convention: a cursive join alone does not prove
that two ordinary words were intentionally written as one. Record ambiguous joins.

After these labels are reviewed, collect a fresh ordinary page for evaluation.
All variants of one page must remain in the same split. The existing append
captures must never become separate training and test examples. Do not use
transcript text or matching word crops from the target page as reference input.

The next experiment is blind whole-page OCR, then page plus readable block crops,
then the same inputs plus a small confirmed reference set. Compare against Tom's
literal transcript using character and word edit error rates; report punctuation,
case, proper names, numbers and unresolved spans separately. Keep both strict and
explicitly whitespace-normalized scores. Do not report the six calibration pages
as evidence of generalization. Keep raw answers, prompts, image hashes and settings
for every run, and review disagreements rather than taking a majority vote.

This workbench does not install an inbox consumer. The existing capture pipeline
continues to supply originals in `~/Paper/inbox`; integration into dotfiles can
follow a measured experiment on reviewed labels and fresh pages.
