# Journal photo sequence

17 original JPEG photographs, 39,261,040 bytes, downloaded from the supplied Drive folder on 14 September 2026. Each original matches Drive's listed size, decodes successfully, and has a unique SHA-256 recorded in `photo-metadata.json`.

The filenames and EXIF capture times agree: 10:15:24.553–10:17:16.478, UTC+02. Drive upload order runs in the opposite direction and is not reading order. Capture timestamps establish the order of photographs; they are not dates of writing.

The deliberate overlaps identify **12 physical notebook pages**. Numbered list continuity and visible facing-page edges support the sequence. Pages without a visible date remain undated.

| Output | Captures | Main content / overlap evidence |
|---|---|---|
| page1.md | 01 | Paper cleanup, system utilization, Tally report card. Written `06/09/26`. Earlier writing is cropped above the supplied photograph. |
| page2.md | 02 | Factory-floor experiment, benchmarks and Bayesian testing. Separate page. |
| page3.md | 03 | `~/today`, project notes and triage. Separate page. |
| page4.md | 04 + 05 | Workstream sweep, then project list 1–14. Bracketed `P.21 of pdf Thomas…` line overlaps. Date literally `09.11.26`, with `911` above; no automatic date-format interpretation. |
| page5.md | 06 | Project list 15–29. One complete portrait photograph. |
| page6.md | 07 + 08 | Project list 30–49. Item 37 and its laptop paragraph overlap; 08 completes the paragraph. |
| page7.md | 09 + 10 | Old notes backlog, FR items. Keyboard charger / Inzone / USB accessories and Thunderbolt dock lines overlap. |
| page8.md | 11 + 12 | “Top 40 things” items 1–24. Item 13, “Also debugging,” overlaps. |
| page9.md | 13 | “Top 40 things” items 25–40, on facing right page. |
| page10.md | 14 | Dotfiles cleanup decision sheet. |
| page11.md | 15 + 16 | Estate/current/next, then goals. Goals heading at bottom of 15 repeats at top of 16. |
| page12.md | 17 | Academic work, Chromium browser, CRM and sales tactics. |

Original files remain unchanged in `originals/`. The original EXIF orientation is 1 for every photograph, but visual inspection requires a 90° counterclockwise turn for all except capture 06, which is already upright. The OCR inputs apply that rotation and the same BICUBIC resize used by Halogen 0.7.0, producing 2208×1664 pixels (1664×2208 for 06), or 3,588 image tokens. No sharpening, generative cleanup, or inferred handwriting is added.

The per-capture Codex reference retains overlaps for like-for-like comparisons with Halogen. The final notebook assembly includes each overlap only once. Tiny fragments of facing pages are excluded, and text missing outside the supplied photographs is never reconstructed by guessing.
