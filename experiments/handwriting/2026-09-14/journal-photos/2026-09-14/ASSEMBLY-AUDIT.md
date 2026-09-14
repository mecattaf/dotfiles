# Assembly integrity audit

Reviewed 14 September 2026 by Codex reader 1. Initial review changed no transcript files. The follow-up authorized formatting-only repairs in `experiment/assemble.py` and regenerated final pages; the rendering repair preserved wording and reviewed-reference bytes. A later final-page-only context pass deliberately normalized3 names, documented below.

**Final content assembly, context normalization and rendering checks pass.** All12 pages preserve the reviewed source stitches apart from exactly3 documented canonical-name substitutions: nick-iconiq on page6, LaCie and Enoki on page7. Nine uncertain spans remain. Literal escaped numbered labels prevent automatic renumbering, and explicit hard breaks preserve numbered/arrow item boundaries.

## Content and sequence checks

All12 notebook page bodies match their expected source stitches **exactly after applying the3 documented canonical-name substitutions and removing presentation escapes and hard-break spaces**, using the locked `codex-reviewed/capture-XX.json` transcriptions. Comparison excludes only the added Page heading, provenance footer, and page1's explicit cropped-writing notice. Expected stitches remove only documented repeated/cropped overlap material.

| Notebook page | Captures | Check |
|---|---|---|
|1|01|Exact transcription; added notice correctly identifies unavailable earlier writing.|
|2|02|Exact transcription.|
|3|03|Exact transcription; Notes arrow and Tally→Kitty correction retained.|
|4|04+05|Capture04's cut bracket line replaced with05's complete bracket line; surrounding prose and list1–14 retained once.|
|5|06|Exact transcription; list15–29, margin fragment and annotation arrow retained.|
|6|07+08|07 items30–36 retained;08 supplies complete37–49. Cropped37 tail and partial boxed note replaced with complete versions. nick-iconiq intentionally normalized from local context.|
|7|09+10|Shared keyboard-accessory and Thunderbolt-dock lines retained once;10's new Asus paragraph follows without a gap. LaCie and Enoki intentionally normalized from exact backlog-front context.|
|8|11+12|Shared item13 retained once;14 immediately follows. Period from11 retained.|
|9|13|Exact transcription; items25–40.|
|10|14|Exact transcription; two subordinate adjustment bullets and crossed-out fragment retained.|
|11|15+16|Clipped goals heading replaced with complete heading from16; divider, prior OCR paragraph and goals retained.|
|12|17|Exact transcription; introductory paragraph and three arrows retained.|

Programmatic numbering checks pass:

- Project list across pages4–6 contains every literal label1–49 exactly once, counting2 in its written inline position after1. The crossed-out number before the ASUS paragraph remains an annotation rather than a live item.
- Top40 list across pages8–9 contains every literal label1–40 exactly once.
- Nine inline `[unclear: ...]` spans remain. Three former uncertain name spans became canonical names with original readings and source evidence recorded in `~/sept14-notepad/RESOLVED.md`. The frozen references retain all original markers.
- No text changes beyond the3 documented substitutions, duplicate paragraphs or missing paragraphs were found relative to reviewed references.

Photo verification covered all five overlap joins:04/05 and07/08 were independently inspected in earlier reading/review, and09/10,11/12,15/16 were re-inspected as paired photo crops for this audit. Captures14 and17 were also visually checked in full. This confirms that the documented repeated material is true photographic overlap, not coincidentally similar prose. The audit does not claim writer confirmation of uncertain words or re-OCR every character anew.

## Rendering findings

### A1 — resolved: page4 automatic ordered-list renumbering

The original source began `1. Tally ... + 2. Minimal ...`, then the next Markdown list item begins `3. “dotfiles ingest flow”`. CommonMark ordered lists use the first marker as their start value and then count consecutive list items. The rendered second item will therefore be labeled2, although its source label is3. The final source item14 will display13. This matters because later notebook entries refer to original item numbers.

Implemented and verified: every line-initial numbered label in final pages uses an escaped period, for example `1\.` and `3\.`. Inline `+ 2.` remains exactly where written. There are no unescaped line-initial ordered labels. No wording or numeric values changed.

### A2 — resolved: numbered/arrow item boundaries

Implemented a presentation-only pass adding two trailing spaces at adjacent nonblank lines where either the current or following line is a numbered/arrow item. This preserves item boundaries, wrapped numbered-item openings, and attached margin notes as CommonMark hard breaks. Unrelated paragraph wrapping is unchanged. The references retain their original text without rendering additions.

## Preserved meaning and limits

Arrows, marginal notes, relevant crossouts and their replacements are present at the joins. Examples include the boxed “Good As is”, boxed “either way”, FR10 correction, zenbook insertion, “Paper printed revamp” addition and nested cleanup arrow. Small differences in original underlining and pen emphasis are not a facsimile requirement of this text assembly and were not converted systematically to Markdown emphasis.

Source01's unavailable top writing is correctly disclosed rather than guessed. Tiny facing-page slivers are correctly excluded. Dates remain literal; chronological interpretation is not silently imposed. The reviewed references and original photos remain available separately for subsequent word-level correction.

## Rendering follow-up verification (before context normalization)

- All12 expected source stitches still match after unescaping only line-initial numbered-label periods and removing trailing hard-break whitespace.
- All files in `codex-reviewed/`, including locked hashes, are byte-identical before and after regeneration.
- 103 numbered/arrow boundaries have explicit CommonMark hard breaks.
- No transcription wording, candidate uncertainty, numbering value, or overlap decision changed.

## Final context-normalization verification

- Page6 uses `nick-iconiq`; page7 uses `LaCie` and `Enoki`. These are the only content differences from the expected frozen-reference stitches.
- `RESOLVED.md` includes all3 original uncertain readings, contextual reasons and source excerpts. Both affected page footers link to it. All cited local source files exist.
- Final pages contain9 uncertain spans, matching the9 entries in `uncertainties.json`. The two numbered sequences still contain1–49 and1–40 exactly once.
- All17 frozen capture JSON SHA-256 values match `codex-reviewed/locked-sha256.json`; the3 original uncertainty markers remain in their frozen capture transcriptions.
- `context-adjudication.json` now records `final_page_patches_applied: true`, `fed_to_qwen: false`, and `benchmark_reference_changed: false`.
- No further notebook or frozen-reference changes were made by this final verification.
