> Current implementation update — September 14: the durable manual one-capture CLI now lives in `~/mecattaf/dotfiles/pkgs/handwriting-intake/`, with coordinator package/backup integration. See `~/mecattaf/dotfiles/docs/handwriting-intake.md` and `DAILY-INTAKE-INTEGRATION.md` for the current contract. All 133 photo-study review tasks are closed with explicit writer/model provenance; retained unreadable inscriptions remain documented. The protocol below preserves the original commissioning analysis. Its statements that a consumer is unimplemented refer to the automatic inbox dispatcher, which still does not run. The first real Huion end-to-end trial, capture-completeness receipts, family-aware examples and audit scheduling remain outstanding.

# Daily Huion OCR: operating protocol and readiness

Audit date: 14 September 2026; refreshed against the completed correction analysis and annotation deployment record. Capture and delivery already run, and writer review is deployed at **https://handwriting.internal** with durable state in `/var/lib/handwriting-annotation`. An automatic inbox-to-OCR consumer remains unimplemented. The daily workflow below is a commissioning proposal; no final OCR recipe is selected until the writer adjudicates the current papers.

The intended daily gesture is simple: write within the Huion's dotted recording area, press its button for each new page, then open the cover near the client laptop to sync. Qwen processes one page at a time on the existing worker. The writer reviews the result and retains both the literal writing and any intended correction. Codex audits the first one to two weeks of real use; no scheduled Codex audit currently exists.

## What is already implemented

| Stage | Verified implementation | Remaining boundary |
| --- | --- | --- |
| Device → client | The client's udev HID-add rule unbinds `hid-generic` and starts system `huion-sync.service` as Tom. A shared lock serializes dump and push. Dump waits three seconds; a failed dump gets one retry after five seconds if still connected. | A successful process exit does not certify that every page was complete. |
| Client holding area | `/var/lib/huion-sync/spool/<YYYY-MM-DD_HHMMSS>/`; complete pages are cleared from the device after nonempty local SVG and JSON exist. PNG is optional. Incomplete pages remain on the device. | The extractor checks file existence/size, not a persisted checksum or explicit `fsync` durability receipt. The device is not the backup after clearing. |
| Client → coordinator | `rsync -a --remove-source-files` into `~/Paper/inbox/<batch>/`. `huion-push.timer` retries pushes after boot and every 15 minutes; it never initiates a dump. | Transfer is per file, not an atomic batch. A failed batch can have some files already received and removed from the client. Remaining files retry. |
| Rendering and OCR | [The workbench](ocr/README.md) renders strokes, groups exact/prefix captures and preserves provisional readings. [The journal experiment](journal-photos/2026-09-14/HALOGEN-RECIPE.md) retains requests, image hashes, answers, timings and parse outcomes. | These are experiment scripts, not an installed inbox consumer. No daily receipt, queue or automatic final export has been verified. |
| Writer review and examples | The deployed [review backend](../mecattaf/dotfiles/pkgs/handwriting-annotation/review.py) serves `https://handwriting.internal` from `/var/lib/handwriting-annotation`. It supports source snapshots, append-only writer events, selected image regions, export and preparation of up to three approved visual examples. | The current papers queue is not an automatic importer for future Huion captures. Prepared example packets do not run inference or change transcripts. |
| Annotation backup | A daily timer writes application-consistent snapshots to `/mnt/nas/documents/handwriting-annotation-backups/<UTC timestamp>/`, including the database, source evidence, queue, exported events and checksum manifest. | This protects annotation state, not an unimplemented daily OCR queue or every original Huion capture. Check backup outcomes; a configured timer does not prove each future backup succeeded. |

Read-only live inspection found the client's push timer active, the last push successful at **2026-09-14 11:36:50 CEST**, and its spool empty. The coordinator inbox contained **four batch directories, seven page triples, 21 files**. This is an inventory snapshot, not evidence that those pages begin ordinary daily use. Existing calibration pages must not start the audit clock.

Sources: [client service declaration](../mecattaf/dotfiles/hosts/client/huion.nix), [pinned extractor package and render patch](../mecattaf/dotfiles/pkgs/huion-notes.nix), [extractor write/delete gate](artifacts/reference/huion-note-x10-ble@6f3f5e7/huion_notes/cli.py), [exported JSON schema](artifacts/reference/huion-note-x10-ble@6f3f5e7/huion_notes/render.py). The older `HANDOFF.md` predates deployment; its “not yet declared” status is historical.

The [annotation deployment record](../mecattaf/dotfiles/docs/handwriting-annotation.md) records verified HTTPS access from the client, 133 initial review tasks, and a first managed NAS snapshot with all 82 checksums matching. The installed service runs the packaged application, not the prototype checkout; startup and code updates preserve existing state rather than reseeding it. The daily snapshot timer is declared in [the annotation module](../mecattaf/dotfiles/modules/handwriting-annotation.nix). These observations establish initial deployment, not continuing backup health or a completed cold-mirror copy.

**Keep OCR separate from printing.** `~/Paper/intake` triggers the print loop; `~/Paper/inbox` receives Huion files. Printer receipts under `~/Paper/printed` do not acknowledge capture or OCR. OCR output must not land in `intake` unless printing is explicitly requested. See [the print service](../mecattaf/dotfiles/home/paper.nix).

## Receive every capture, finalize only a verified page

Current filenames are `page{N}-{DD}-{MM}.{json,svg,png}`. The number restarts after clearing, and the date is the dump date. Preserve the batch directory, filename and receive time; do not infer the writing date or unique physical-page identity from the basename. A sample JSON contains `page`, `max_x`, `max_y`, `max_press` and `strokes`—no writing timestamp or completeness field.

There are two distinct incomplete states. Rsync may still be delivering a file group. Separately, the extractor can write a partial device page, retain it on the device, then push its exported files. Stable, valid SVG/JSON cannot distinguish the latter from a complete page. Parsing successfully and having a PNG do not close that gap.

The smallest capture-side addition before unattended finalization is a **per-page completion receipt** from the extractor: capture ID, file hashes/sizes, capture-complete status, device-page index, extractor version, dump time and save outcome. Persist it atomically after the source files are durably written, before device clearing; record clear outcome separately. A receiver must verify the declared hashes even if the receipt arrives before another file. This change is proposed, not installed. Existing receiptless files can still be rendered and reviewed with `capture_completeness: unknown`; keep that status visible until the writer or a later complete capture resolves it.

For the coordinator consumer, use one local state database and immutable source snapshots. A proposed home is `~/Paper/ocr/`, with objects keyed by source hash, individual attempt directories and receipts. Leave received originals in `inbox`; no automatic source deletion is needed for this pilot.

- **Capture identity:** original relative batch/path plus SHA-256 of the exact JSON bytes. Preserve SVG and any PNG hashes too. Any changed bytes at an old path become a new version, never an overwrite of evidence.
- **Content identity:** canonical ordered strokes plus coordinate/pressure limits and renderer version. The workbench's exact/prefix comparison is a useful starting point; compare limits as well as strokes. An extended prefix is a later version, not a second unrelated page. Empty or unrelated identical captures still retain their separate capture events.
- **Physical-page family:** retain all related versions under one family, choose the complete version explicitly, and keep all variants in the same evaluation partition. Ambiguous relationships require review; filename resemblance is insufficient.
- **Attempt identity:** capture/content version + recipe hash + unique attempt ID. The same received file may be observed repeatedly without creating duplicate exports. A retry retains its own raw evidence.

The proposed durable states are:

`discovered → waiting_for_files → received_validated → queued → processing → review_required → writer_resolved → exported`

Capture completeness is a separate field throughout. `retry_wait`, `needs_capture_review`, `unreadable` and `deferred` remain visible outcomes; they are not success. A valid model answer still goes through review during the pilot. “Exported” means a particular reviewed revision was written successfully, not that its source may be removed.

At receive time, parse and validate the JSON and required SVG, snapshot and hash the originals, then recheck source hashes before committing the receipt. Missing PNG can be regenerated from valid strokes. Without a receipt, two unchanged observations help avoid copying an active transfer but do not prove device completeness. Interrupted local writes use temporary files and atomic rename; the state transition follows persisted evidence. An expired processing lease makes a crashed job eligible again without losing its earlier request or duplicating a final export.

Network/time-out/temporary server errors should get at most two automatic transport retries with a delay, then remain visibly pending. Preserve response bytes even on parse failure or length termination; do not turn malformed JSON into an empty “successful” page. A response lost after inference may cause another inference on retry; that is acceptable if the evidence and final publication remain idempotent. This is a proposed guarantee to implement and test, not a claim about the current scripts.

## Initial appliance recipe to test

Start with **one whole-page request, thinking off**, using the existing Flash server at `http://worker:8731/v1/chat/completions`. Verify model identity with `/health`; the request's model string alone is not a selection guarantee. Retain the audited request shape: `enable_thinking:false`, `reasoning_effort:"medium"`, `temperature:0`, `drafter:"mtp"`, `stream:false`, and a 16,384-token answer budget. This build defaults to enabled thinking/xhigh if those options are omitted. Keep the fixed system prefix separate from the changing image and page instruction.

Render directly from the stroke JSON with the deployed 1.2-width round strokes and recorded coordinates. Preserve the raw pressure values. Record canvas size, scaling, orientation and image hash in every request. The server does not perform EXIF orientation; the phone-photo preprocessing must not become a blind rotation rule for already upright Huion renders. Never infer that a `stop` finish or a valid JSON object means the page is complete.

Use **all reported difficulties** to build the review queue: uncertain, hard and unreadable. Add coverage checks for missing lines or margins, suspicious numbering gaps, cut edges, empty text despite ink, cancelled text, and an uncertainty span that is repeated or absent from the transcript. These are alerts to inspect, not instructions to invent a missing word or renumber a list. Coverage checks cannot establish correctness alone; the writer should compare every full page during the initial fortnight.

The development [certainty audit](journal-photos/2026-09-14/runs/baseline/certainty/CERTAINTY.md) illustrates why: off-mode “hard only” directly covered 1/85 normalized disagreement operations, while all reported flags covered 29/85. These are provisional-reference alignment operations, not writer-confirmed errors or calibrated confidence. Omitted words may have no output span to flag.

For a located difficult span, propose **one low-thinking crop retry**, with at most three provenance-backed vocabulary candidates. Bound automatic crop requests to two per page initially; the remaining flags stay in review. Only retry a uniquely located target with an adequate image region; otherwise let the writer select it. A changed reading is a candidate, never an automatic writer label. Keep the original reading and the retry side by side. A missing/repeated target cannot be safely replaced by ordinary string substitution.

The completed [correction analysis](journal-photos/2026-09-14/runs/correction/CORRECTION-ANALYSIS.md) records **68 finished attempts, 67 usable responses**. Medium with hints on capture12 returned a contradictory clear target without a nonempty reading; validation rejected it, preserving the response without retrying it inside this comparison. Low with hints improved **6 of 17 targets**—four development and two held-out—with ten unchanged, one unresolved-reference target, zero observed regressions and a seven-operation reduction in known-word disagreement. Development supplied five of those seven operations. Off crop alone improved none; off with hints improved three; medium with hints improved four of its 16 usable targets. These counts include valid proposals regardless of self-reported clarity; they are not counts of writer-accepted corrections.

The bounded low retry proposal was motivated by development results; the held-out results now provide a separate check. All scores still use provisional reviewed Codex readings, not writer truth. The comparison tests one selected target per photo, so the proposed two-retry daily cap is an operating limit, not a tested two-target accuracy claim. Writer adjudication and ordinary Huion pages must decide the final recipe and whether hints or visual examples save review work.

For the retry, retain the audited 4,096-token shared thinking/answer budget and explicitly set enabled thinking with `reasoning_effort:"low"`. No model restart, alternate model, new engine or kernel tuning is needed. Prompt caches are an observed optimization: record `cache_n`, but do not require a hit or claim a vision-cache saving.

## Append-only correction history and reusable examples

The deployed annotation backend stores append-only events in `/var/lib/handwriting-annotation/resolutions.sqlite3`; operation IDs make a repeated save idempotent and revisions reject stale edits. Current actions are `resolved`, `absent`, `unreadable`, `deferred` and `reopened`. Keep literal text separate from intended spelling, notes and tags. Huion/Huyon can share an intended referent while preserving what was literally written.

**Keep the entire trailing correction history for offline adaptation.** Each new writer save appends a revision rather than replacing the earlier event. The source task and evidence snapshot preserve the original model reading; events retain the successive writer readings, intended corrections, actions, notes, time, previous revision, source/image hashes and selected region. Together they let a later offline review reconstruct what was proposed, corrected, reopened and corrected again. Reopening or revoking reuse changes current eligibility without deleting that history. The queue displays the latest decision; it is not a substitute for the complete event log.

The existing export operation emits every event in sequence as JSONL, and each managed NAS snapshot includes `events.jsonl` alongside the database and evidence. For a future daily transcript export, append a dated correction-history section after the literal transcript, or a linked per-page JSONL sidecar, identifying event revisions and their source hashes. That per-page trailing export is proposed, not currently an automatic notebook feature. Treat it as a reproducible view of the authoritative append-only log; keep older entries when a later correction supersedes them. Offline analysis needs both the log and its referenced evidence, not just the final cleaned text.

A reusable visual example requires a writer-resolved event, explicit reuse choice, an image selection, and `example_text` describing **exactly the ink inside that selection**. Resolving a line does not confirm every candidate word crop. Raw Qwen, Codex and Claude agreement is not a writer label; the experiment's 630-term provisional vocabulary must not be presented as confirmed examples.

The existing `compile` method prepares at most three examples from the latest eligible writer events, checks source/image identities and excludes the target `page_key`. Thus the full history is retained for audit and offline analysis, while only the **current, explicitly approved** crop reading can enter a new example packet. Superseded, deferred, reopened or reuse-disabled events remain in history but are excluded from current examples. The method makes no inference call. Future daily integration must exclude the entire target physical-page family, including earlier prefix captures and alternate photos, rather than merely a filename. Old packets remain part of their historical request evidence.

Version each recipe with exact prompt bytes, preprocessing, options, engine identity, selected example revisions/hashes and retrieval policy. Save the exact packet sent with each attempt. Begin with text hints as the measured proposal; visual examples are a separately measured recipe change. Offline adaptation here means inspecting the accumulated correction history, selecting confirmed visual examples and evaluating versioned prompts on fresh pages. **No weight training or model-parameter update occurs.** Use the deployed daily snapshot mechanism and check its receipts; copying a live SQLite file alone is not a complete backup. No automatic notebook rewrite or example promotion is installed by this document.

## First 14 days and Codex audit

After the current papers are adjudicated and the consumer passes commissioning, record an explicit `first_real_huion_page` marker: physical-page family, source hashes, received time, writer-designated writing date and recipe version. This marker starts **Day 1**. Today's phone-photo experiment and earlier Huion tests do not. The marker, daily report and audit-due reminder still need implementation; no audit timer or future Codex session has been scheduled.

During Days 1–14, process serially and have the writer review the whole page, including apparently clear lines. Record review status per physical page, not just per flagged word. Preserve unresolved and intentionally unreadable material; never count a deferred page as correct. Keep output revisions in a separate transcription destination, proposed `~/Paper/transcribed/`, with links to source and decisions. The existing `~/sept14-notepad/pageX.md` collection remains its own reviewed project.

| Daily measure | What to retain |
| --- | --- |
| Delivery and completeness | Captures, unique page families, prefix revisions, receipt completeness, waiting-file count, oldest pending age, failed/retried transfers and any unexplained missing page. |
| OCR behavior | Recipe version, page/attempt ID, baseline and retry wall time, finish/parse outcomes, token/cache counters and coverage alerts. Count transport retries separately from deliberate crop retries. |
| Writer work | Pages reviewed, flagged and unflagged corrections, review time, unresolved items, and reusable examples explicitly approved. |
| Quality | Word/character disagreement against writer literal readings, with normalization stated; names, numbers, missing content and meaningful marks separately. Compare baseline with each proposed correction, including regressions and rejected suggestions. |
| Flag usefulness | Among reviewed flags, how many required a literal correction; among all writer corrections, how many had been flagged. Report omissions separately from exact-span detection. |
| Resources | Worker idle and sampled active unified-memory accounting, memory delta, request duration and GPU busy time. Record concurrent workload; do not add overlapping KFD/GTT/RSS counters or derive safe spare capacity from `MemAvailable`. |

The phone-photo [serial runtime](journal-photos/2026-09-14/runs/fresh-off/RUNTIME.md) is a starting operational reference: 17 requests, median 22.73 seconds, KFD-system accounting about 113.15 GiB with no sampled increase during that pass. It is not a promise for new rendering sizes or a physical RAM budget for other processes. Record daily Huion measurements using the same accounting views; power draw is outside this requirement.

At Day 7, inspect backlog age, capture completeness and correction regressions. At Day 14—or within the requested 1–2-week window if enough real pages are available—prepare a Codex audit bundle and explicitly launch the review. Include all page/source manifests, original off answers, retries, writer event revisions, recipe versions, latency/resource summaries and unflagged corrected lines. Codex should inspect images against literal decisions, withhold approval on unresolved items, and assess whether the bounded retry saves writer time without increasing mistakes. Missing days or too few pages are limitations, not a reason to relabel the photo experiment as daily evidence.

Use page families reviewed earlier as development data; keep later fresh pages out of recipe selection and example retrieval until evaluated. Any recipe change creates a new version and its own before/after comparison. A material dropped page or export conflict calls for immediate investigation rather than waiting for Day 14.

## Smallest next deployable unit

One coordinator consumer can own scanning, a local SQLite queue, serial requests and review-item export. A systemd oneshot plus periodic rescan is sufficient; use a file watch only as a wake-up optimization. Halogen and the existing client transfer remain the serving and transport boundaries. Pair this with the small capture-completeness receipt described above. Do not add a distributed queue or train weights to solve the handoff.

Before enabling it for ordinary pages, exercise these bounded fixtures offline, using saved responses instead of GPU calls:

1. Deliver SVG/JSON/PNG in different orders, including a missing optional PNG, receipt-before-files, changed hash and interrupted transfer. No premature finalization or discarded source.
2. Send the same capture twice, reuse `page1` in a new batch and extend an earlier stroke prefix. Preserve provenance, distinguish new content and avoid duplicate export.
3. Export an incomplete device page followed by its complete version. The first remains explicitly incomplete; stable files and exit zero must not hide it.
4. Crash between request, response, parse, state commit and export. Resume visibly with retained attempts and one publication per reviewed revision.
5. Replay timeout, malformed JSON, `length` termination, empty-with-ink and repeated/absent uncertainty targets. None becomes an accepted empty or fabricated page.
6. Review a missing line, margin note, meaningful arrow, crossout and nonconsecutive list numbering. Preserve literal content and surface ambiguity without automatic repair.
7. Save a writer decision twice, reject a stale revision, reopen it and revoke example reuse. Future packets use only current approvals and exclude every target-page variant.
8. Restore a source/database snapshot into a fresh state location and reproduce one export from recorded hashes and revisions. Never overwrite the running state during this test.

Commissioning is complete only when one real received page can be traced from capture receipt through saved inference and writer decision to a reproducible export, with retries and incomplete captures visible. This document records the remaining work; it performs none of those deployments or model calls.
