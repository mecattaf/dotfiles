# Journal handwriting OCR experiment — 14 September 2026

Status at the September 14 source-archive snapshot: all **174 inference attempts** finished (157 initial calls plus the newly requested 17-photo no-thinking confirmation). The annotation website is live at https://handwriting.internal. The writer finished all 26 priority items: 24 resolved and two unreadable; ten literal notebook changes and 14 unchanged confirmations were recorded. Model-assisted reconciliation of the separate 107 Qwen flags is imported: 101 resolved and six unreadable model reviews, with 107 saved and zero rejected. The app now has 125 resolved and eight unreadable tasks, zero pending, comprising 26 writer decisions and 107 model reviews; model reviews are not writer labels. Seven unique uncertain inscriptions remain because the margin has duplicate tasks. One additional model-verified notebook correction, hygiene → higiene, is separate from the ten writer changes. Real-Huion intake implementation and tests are underway, with commissioning still pending.

## The collection and reviewed notes

17 original phone photographs reconstruct into 12 physical notebook pages. Capture timestamps, visible continuations and the deliberate overlaps establish the sequence; Drive upload order does not. Four Codex readers transcribed separate groups, followed by independent cross-review. All originals, first readings, revisions and source hashes are retained.

The usable notes are in [/home/tom/sept14-notepad](/home/tom/sept14-notepad), with `page1.md` through `page12.md`. The original nine unresolved readings and 17 additional cross-reader differences were presented as 26 priority items; all now have writer decisions. Two writer-marked unreadable locations remain explicit; after the additional model review there are seven unique uncertain inscriptions across the collection (eight unreadable tasks include a duplicate margin). Three names—nick-iconiq, LaCie and Enoki—were resolved using matching older local notes with explicit provenance. Those final notebook normalizations were not added to the frozen benchmark references or Qwen hints.

The notebook now includes targeted writer adjudications, not a complete writer verification of every word. The frozen benchmark references remain the earlier reviewed Codex readings. Scores below measure disagreement with that unchanged provisional reference. Uncertain reference spans are excluded from the known-word score; the complete alignment remains inspectable. Physical-page results count the deliberate overlaps once. Per-photo scores are supplementary because clipped fragments and duplicated text can otherwise inflate differences.

## Comparison design

- Vanilla Halogen: all 17 photographs, four distinct settings—thinking off, low, medium and xhigh. No personal glossary, examples or reference transcript in the requests. Mode order rotates by photo.
- Serial fresh-photo confirmation: all 17 photographs with thinking off, checking actual cache reuse. This represents a warm resident appliance receiving different photos; it is not a server restart or a cold-weight test.
- Targeted correction: one eligible self-reported uncertain span per photograph, native crop, at most three vocabulary candidates. Compare crop alone with thinking off, then hints with off, low and medium. The 630-term vocabulary and selection policy were developed only on photos01–08 (physical pages1–6); photos09–17 are held out on separate physical pages. Crop locations receive visual checks before inference.
- Bounded detail probe: the densest photo in each partition, selected by baseline output length without reference-error input, receives two overlapping tiles. Four additional calls test whether greater image detail helps.

The runs are serial and use the existing Flash deployment. No server flags, model weights or production pipeline are changed. All generated correction candidates remain separate from the reviewed notebook.

## How the appliance works

The deployed path and request flags were checked against the running Halogen0.7.0 frontend, tokenizer, startup log and health endpoint. The server loads its shipped quality overlay and vision tower. Input images are rotated explicitly, decoded RGB, and resized to the server's area/stride rules. The full-photo inputs use3588 image tokens. Each request sets temperature0, MTP drafting and an explicit shared thinking/answer token budget. JSON is requested in the prompt and validated locally; this build has no constrained JSON decoding.

The stable OCR system instruction remains byte-for-byte fixed; each photo and any correction candidates go in the user-message tail. Cache mode2 can change numerical behavior. Mixed-mode calls can reuse nearly the whole same-photo token prefix, so their timing must be read alongside the separate serial pass. Cached-token counters do not prove that all vision-tower work was skipped.

The lookup is a small candidate retrieval step. It never treats the nearest spelling as truth. Each candidate has source provenance, and Qwen must still read the crop. Self-reported difficulty supplies a retry signal, not a probability of correctness. The experiment explicitly measures unflagged disagreements, reference-matching alerts and correction regressions.

See [HALOGEN-RECIPE.md](HALOGEN-RECIPE.md) for exact prompts, flags, cache interpretation and how the Sunday optimization work applies. Compiling a future recipe means freezing tested instructions, examples, preprocessing and checks; no model-weight fine-tuning has occurred here.

## Measurements and proposed daily recipe

Start the daily trial with whole-page **thinking off**, then offer a **low-thinking crop retry with a few relevant hints** for selected difficult spans. Keep proposed corrections reviewable. Higher thinking on every whole page bought little in this sample.

| Whole-page thinking | Mean seconds/photo | Known-word disagreement across 12 physical pages |
| --- | ---: | ---: |
| off | 22.79 | 120/2223 (5.40%) |
| low | 33.68 | 118/2223 (5.31%) |
| medium | 38.08 | 134/2223 (6.03%) |
| xhigh | 83.64 | 115/2223 (5.17%) |

These are disagreement rates against the provisional Codex reference, not writer-confirmed accuracy. Deliberate overlaps count once. The mixed-mode timings include same-photo prefix reuse. The separate [fresh-photo pass](runs/fresh-off/RUNTIME.md) took **23.94 seconds mean, 22.73 seconds median**, with only 290 shared-system tokens reused on every request. All 17 parsed answers exactly matched the original off pass. The newly requested [writer-era vanilla confirmation](runs/writer-confirmation-off/CONFIRMATION.md) added 17 more serial calls with no labels or hints: **406.51 seconds total, 23.91 seconds mean**, zero reasoning tokens and byte-identical answers to all 17 earlier fresh-off responses, including uncertainty flags. Stable outputs preserve both correct readings and existing errors; writer decisions were not supplied to Qwen.

The [crop comparison](runs/correction/CORRECTION-ANALYSIS.md) completed all 68 requests; 67 passed schema validation. Medium/capture12 returned a contradictory found/reading/difficulty combination and remains a recorded rejection without a hidden retry.

| Crop retry | Improved / regressed targets | Known-word difference from off | Mean additional seconds |
| --- | ---: | ---: | ---: |
| off, crop alone | 0 / 0 of 17 | 0 | 9.92 |
| off, crop and hints | 3 / 0 of 17 | −4 | 8.77 |
| low, crop and hints | 6 / 0 of 17 | −7 | 16.76 |
| medium, crop and hints | 4 / 0 of 16 usable | −5 | 16.37, including rejected attempt |

Low with hints improved four development targets and two held-out targets. Ten were unchanged and one touched unresolved reference text. Applying all its valid suggestions gives 113/2223 (5.08%) physical-page disagreement, but some useful suggestions still report uncertainty. This supports a bounded review-assisted trial, not automatic acceptance or a statistically established winner. The conservative off-crop/low-hints clear-agreement policy produced no improvements. The provisional 630-term vocabulary is not a writer-approved handwriting atlas.

The [two-photo tiling probe](runs/tile-probe/TILE-PROBE.md) did not justify routine tiling: capture06 had an ambiguous overlap and was refused; capture10 worsened from 13 to 17 known-word differences and took 41.56 seconds instead of 22.67. Raw tiles and failed stitching evidence remain available.

## Unified memory and GPU activity

The full-photo baseline measured **113.119 GiB (121.461 GB)** of warm-idle KFD system accounting and **113.166 GiB (121.511 GB)** at the sampled peak: **+0.047 GiB, about 50 MB**. The fresh-photo pass stayed at **113.151 GiB (121.495 GB)** with no sampled incremental KFD allocation; correction added about 0.006 GiB. Active GPU busy averaged 97.26% during the first fresh pass, versus 0% initially idle. The latest 17-photo confirmation measured **113.157 GiB (121.502 GB)** KFD accounting with **zero sampled growth over idle**, and 97.23% active GPU busy. Its separate engine/frontend RSS peaks rose by 0.044/0.056 GB; these overlapping views must not be summed.

Thus the earlier “110 GB” report is approximately the right scale if it meant GiB; the observed warm OCR footprint is around **113 GiB / 121.5 decimal GB**. This is driver allocation/registration accounting, not an exact census of physical resident RAM. KFD, GTT and process RSS overlap and must not be added. The earlier small-Huion baseline was about 112.31 GiB; a separate large-image probe left roughly another 0.82 GiB resident. The 50 MB warm delta must not be described as the entire cold vision cost.

The host has 125.085 GiB total. Simple subtraction leaves about 11.9 GiB before OS and other workload needs, not a guaranteed safe allocation allowance. Its much larger MemAvailable figure includes model-backed pages that cannot be assumed safely reclaimable. See [baseline runtime](runs/baseline/RUNTIME.md), [fresh runtime](runs/fresh-off/RUNTIME.md), and the earlier [/home/tom/huion/ocr/BENCHMARK.md](/home/tom/huion/ocr/BENCHMARK.md). Power draw was not collected.

## Claude comparison and targeted writer adjudication

All 17 supplied Claude first readings were preserved and compared; their files self-report claude-opus-5. Claude cross-review was not run. [Physical-page comparison](claude-comparison/COMPARISON.md) found 56/2223 (2.52%) known-word disagreement against the cross-reviewed Codex reference. The unequal review budgets and unconfirmed reference mean this is not a model accuracy ranking.

The live [annotation queue](https://handwriting.internal) contains **26 priority items**: nine original unresolved readings and 17 substantive Claude/Codex differences. The writer resolved 24 and marked two unreadable. The immutable [application receipt](writer-review/20260914T100934Z/application-20260914T101208Z/application-receipt.json) records ten literal notebook changes and 14 unchanged confirmations. Another 107 Qwen uncertainty items were separately reconciled under explicit user authorization: 101 resolved and six unreadable model reviews were imported successfully, with [107 saved and zero rejected](model-review/import-receipt.json). The combined app has 125 resolved, eight unreadable and zero pending tasks. Seven unique uncertain inscriptions remain after deduplicating the margin. A separate model-verified literal notebook correction changed hygiene to higiene; it is not counted among the ten writer changes. Their provenance remains model-assisted; they cannot become writer-approved reusable examples through model agreement alone. Items retain source photos, line context, reader provenance, literal/intended text and handwriting notes.

Self-reported difficulty misses real disagreements. On development captures, off-mode hard-only flags covered 1/85 known-word alignment operations; all difficulty flags covered 29/85. [The certainty audit](runs/baseline/certainty/CERTAINTY.md) also records reference-matching alerts and unflagged omissions. During the initial daily trial, review whole pages as well as flags.

## Trailing corrections and offline reuse

The deployed application keeps append-only writer events in `/var/lib/handwriting-annotation/resolutions.sqlite3`, linked to immutable task/source/image snapshots. Every revision retains the literal correction, intended spelling separately, note, tags, image selection, timestamp and prior revision. Reopening or withdrawing reuse keeps earlier history while removing that example from future packets.

A local compiler can retrieve up to three explicitly approved visual examples, with exact crop labels and provenance, excluding the target page. It prepares a packet without making any model call. Exported `events.jsonl` plus `tasks.json` and evidence form the portable offline record; JSONL alone contains references to that evidence. Daily consistent snapshots go to `/mnt/nas/documents/handwriting-annotation-backups/`; the initial 82-file checksum manifest and backed-up database passed verification.

The daily inference consumer does not yet read these packets automatically, and no weights have been trained. [DAILY-OCR.md](/home/tom/huion/DAILY-OCR.md) records commissioning requirements, including capture-completeness receipts and a Codex audit after 1–2 weeks of actual daily use. No future Codex session is scheduled. The current notebook has received the targeted writer decisions. The real-Huion intake implementation and tests are now underway; this source archive does not assert that commissioning is complete. Canonical deployment status will be recorded in `~/mecattaf/dotfiles/docs/handwriting-intake.md`. [Deployment and backup operations](/home/tom/mecattaf/dotfiles/docs/handwriting-annotation.md) describe the running service.

## Verification

The managed website and image API returned HTTP 200 from the client with normal TLS verification. Its initial 14 backend tests and disposable-state browser interaction checks passed; the experiment suite passed 41 tests. Subsequent annotation/intake revisions are being tested separately; the initial counts are historical deployment evidence. Test annotations were never written into the live writer record. All original photos and frozen model references remain preserved. Dotfiles deployment is recorded in local commit `194d2d9f`.

## Evidence and reproduction

[Collection README](README.md), [photo sequence](SEQUENCE.md), [assembly audit](ASSEMBLY-AUDIT.md), [context adjudication](CONTEXT-ADJUDICATION.md), [physical-page baseline](runs/baseline/reconstructed/PAGE-QUALITY.md), [certainty audit](runs/baseline/certainty/CERTAINTY.md).
