# Handwriting intake: manual Huion pilot

This coordinator CLI receives **one explicitly selected Huion JSON/SVG group**, submits one page to the existing Halogen Flash server, and prepares a writer-review packet. It has no scanner, inference timer, device-clear operation, automatic annotation acceptance, or new model service. Received originals remain untouched.

The packaged command defaults to `/var/lib/handwriting-intake`; an explicit `--state PATH` before the subcommand overrides it. Direct Python execution defaults to `~/Paper/ocr`.

```bash
# Offline: snapshot one selected real capture. SVG is required; PNG is optional.
handwriting-intake receive ~/Paper/inbox/BATCH/page1-DD-MM.json

# Use the returned capture_id. This makes one serial model request.
# Legacy exports have no completion receipt, so acknowledge unknown completeness.
handwriting-intake run CAPTURE_ID --allow-unknown

# Import the returned review_packet path into the existing annotation service.
handwriting-annotation --state /var/lib/handwriting-annotation import-items --items REVIEW_PACKET

# After the writer resolves the entire capture on handwriting.internal:
handwriting-intake export CAPTURE_ID \
  --review-state /var/lib/handwriting-annotation \
  --output-dir ~/Paper/transcribed

handwriting-intake status
handwriting-intake snapshot --output /path/to/NEW_VERSIONED_DIRECTORY
```

`run --retry` is an explicit additional attempt. A successfully processed capture under the same recipe is otherwise idempotent. Failed or interrupted attempts require that explicit retry; their directories and raw responses remain. There are no automatic transport retries in this manual commissioning step. The process lock serializes intake mutations and OCR; an interrupted process releases the lock, and the next run marks stale processing attempts interrupted before requiring a retry. `/health` also refuses a busy or unexpected worker model. It cannot exclude another external client arriving after the check.

## What is and is not established by a receipt

Both JSON and SVG must be nonempty and parse. Optional PNGs are validated when present. File bytes are read twice and rechecked after snapshotting. Missing, malformed or changing sources create a durable `waiting_for_files` observation rather than a processable capture. Waiting includes invalid files requiring investigation; there is no hidden retry daemon.

A receipt hashes the exact original file bytes and source path. Ordered strokes and coordinate/pressure limits have a separate content hash. Changed bytes at an old path create a new capture version. Re-observing identical bytes at the same path does not duplicate the capture. Identical ink from another path retains its own capture receipt; content hashes expose the relationship, but the pilot does not merge physical-page families or silently reuse another capture's writer decision.

**Every current legacy export remains `capture_completeness: unknown`.** Stable files, valid JSON, a rendered PNG, a `stop` response, or writer review do not prove a complete physical device page. No writing date is inferred from filenames. Extractor completion receipts and physical-page family reconciliation are still needed before unattended finalization.

Sources are content-addressed and immutable in `objects/`. SQLite pins receipt hashes. Receipt-before-database crashes recover only when existing receipt identity and evidence match the newly observed source. A receipt or snapshot modified after import is rejected before processing/export.

## Rendering and request

The renderer uses the deployed 900×1190 canvas, 15-pixel padding, recorded coordinates, fixed 1.2-width round strokes and no photo rotation. Pressure values remain in the original JSON. It regenerates geometry from validated JSON rather than executing the received SVG. Rasterization is explicitly versioned as `huion-round-1.2-pillow5x-v1`: a fivefold grayscale Pillow render, downsampled to the canvas, then RGB/BICUBIC to the audited 896×1184 Halogen stride shape. This preserves the selected thin-stroke geometry but is **not claimed bitwise equivalent to ImageMagick's SVG rasterizer**. The package's Pillow version, recipe, generated SVG/PNG, image hash and program source are retained per attempt. The next real-Huion trial must assess this renderer too.

Requests use the experiment's exact fixed OCR system/user messages with `enable_thinking:false`, `reasoning_effort:"medium"`, `temperature:0`, `drafter:"mtp"`, `stream:false`, and `max_tokens:16384`. They contain one image, no earlier page and no examples. Thinking and answer share the output budget. Model identity/vision/readiness are checked through `/health`, not inferred from the request model label. Raw response bytes and answer text remain even when finish/schema validation fails.

## Review and publication

A usable attempt creates an annotation-compatible collection and `items.json` packet inside its attempt directory. It contains one `page_review` item for the entire transcript and separate grouped `qwen_uncertainty` items for all nonempty self-reported spans. Previous/current/next lines, full text, repeated/missing span counts, cut-edge/empty-page notices, unknown capture completeness and source/image provenance remain available. Resolving the whole capture does not silently resolve individual doubts; resolving doubts does not finalize the whole capture.

Publication requires the **latest whole-capture event** for the latest usable attempt to have `actor == "writer"`, `action == "resolved"`, a literal reading, and matching capture/attempt/source/image/receipt identities. A model-assisted decision cannot pass this gate. Publication holds a short annotation database write reservation to serialize against simultaneous writer edits, without adding or changing annotation events.

Each published writer revision gets its own directory containing `literal.md`, separate `provenance.json`, complete related correction history up to that publication in `correction-history.jsonl`, and a checksum manifest. Same-revision exports are idempotent, later writer revisions retain older exports, and edited output files are never overwritten. A complete matching publication left before its database commit can be adopted on retry; an incomplete output directory requires inspection. Files are never placed in the automatic print intake.

Approved visual examples are deliberately **not consumed yet**. Legacy capture-family identity is unknown, so excluding only a filename would risk showing the target's earlier version as an example. The annotation service's writer-only, explicit-reuse library remains separate until family exclusion can be demonstrated.

## State and backups

`intake.sqlite3` contains observations, capture receipts, attempts and export receipts. `intake.lock` serializes mutations. `objects/`, `receipts/`, and `attempts/` retain immutable source/request/response evidence. External transcript exports are tracked by checksums.

`snapshot --output NEW_DIR` waits for the global intake lock, uses `SQLite.backup`, copies the immutable evidence trees and exact tracked export files, and writes `manifest.json` with `status: complete` last. It refuses an existing destination and never prunes. The managed backup wrapper can supply a versioned NAS directory. Failure leaves an incomplete directory without a complete manifest for inspection; use a new destination for another attempt. Backups preserve absolute historical request/review paths, so restore to the same state path for direct continuation. They do not alter or acknowledge the client's extractor/spool.

## Validation and commissioning limits

The offline suite exercises partial/changing inputs, duplicate/versioned imports, receipt crash recovery, explicit unknown completeness, source tampering, exact off-mode request shape, raw failure retention, explicit retry/interruption bookkeeping, whole-page gating, model-review rejection, revision history, export crash recovery/edited-target refusal, and consistent immutable backups. No test calls a model.

A real Huion page still needs an operator-run end-to-end trial. The pilot is intentionally manual: capture-side completeness receipts, family matching, automatic dispatch, automatic first-fortnight scheduling, safe visual-example integration, and unattended finalization remain outside this command.
