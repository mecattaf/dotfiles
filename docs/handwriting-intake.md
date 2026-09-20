# Handwriting intake

The everyday model is the existing Halogen Flash appliance on `worker:8731`.
Read one page at a time with thinking explicitly disabled. Preserve the source,
request, raw answer and subsequent corrections. The review site is
**https://handwriting.internal**; deployment, state and NAS backup instructions
are in [handwriting-annotation.md](handwriting-annotation.md).

## Where the mechanism accumulates

| Material | Canonical location |
| --- | --- |
| Running code and deployment | `pkgs/handwriting-annotation/`, `pkgs/handwriting-intake/`, `modules/handwriting-annotation.nix` in this checkout |
| Experiment source archive | `experiments/handwriting/2026-09-14/`, with original paths and SHA256 manifest |
| Append-only correction decisions and image/reference evidence | `/var/lib/handwriting-annotation/` |
| Real-Huion receipt/request/answer/export evidence | `/var/lib/handwriting-intake/` |
| Most corrected current notebook | `~/sept14-notepad/page1.md` through `page12.md` |
| Full original study and reference outputs | `~/huion/`, preserved separately in the NAS workbench archive |
| Consistent annotation backups | `/mnt/nas/documents/handwriting-annotation-backups/` |
| Consistent intake backups | `/mnt/nas/documents/handwriting-intake-backups/` |

## What the September photo trial established

Seventeen phone captures reconstruct into twelve physical pages, with deliberate
overlap counted once. Four Codex readings and independent cross-review provide
one reference; a separate Claude first pass provides another. Neither is full
writer-confirmed ground truth. Tom reviewed the 26 priority differences: 24
resolved and two unreadable. Ten literal changes were applied to
`~/sept14-notepad/pageX.md`, with fourteen unchanged confirmations and a trailing
per-page history. Original photographs and model references remain frozen.

All 133 annotation tasks are now closed: 125 resolved and eight unreadable,
with 26 writer decisions and 107 model-assisted decisions. The eight unreadable
tasks represent seven distinct inscriptions because the margin note was flagged
twice. They remain documented in the notebook; zero pending tasks does not erase
these literal uncertainties. One further image-verified model correction preserves
`higiene` instead of normalized `hygiene`, separate from the ten writer changes.

The other 107 flags were Qwen's own doubts, not 107 newly discovered mistakes.
At Tom's request, reconcile them using the existing Codex/Claude readings and
his decisions, retaining source evidence. Record these as `model_review`
events. Do not present them as writer confirmations or ask him to review every
flag again. Bring back only a conflict the available evidence cannot resolve.

The home page counts reviewed and remaining items separately, opens no queue
implicitly, and clears the form when a queue is exhausted. “You're all caught
up” means no pending or deferred annotation tasks. It does not claim that
unreadable ink became legible or that every physical page is complete.

## Local inference recipe

Use `/health` for server identity and vision readiness. The request model string
alone does not select or verify the engine. Use the existing chat-completions
endpoint, `halogen-qwen3.8-flash-next`, `enable_thinking:false`,
`reasoning_effort:"medium"`, `temperature:0`, `drafter:"mtp"`, `stream:false`,
and `max_tokens:16384`. The budget includes thinking when enabled. Request JSON
in the prompt and validate it locally; do not add unsupported constrained-output
flags. Retain exact prompt bytes, preprocessing, image hash, engine metadata,
finish reason and token/cache counters for each attempt.

Keep the system instruction stable and changing image/text in the user tail.
Prompt-cache hits are an optimization, not persisted handwriting knowledge.
The explicitly requested fresh confirmation completed 17/17 photos in 406.51
seconds (23.91 seconds each), with zero thinking tokens. Every answer was
byte-identical to the previous fresh off pass. Warm KFD accounting remained
113.157 GiB with no sampled increment. This confirms repeatability, including
remaining uncorrected vanilla readings; it is not automatic learning from the log.
Low-thinking crop retries with a few relevant hints improved six of seventeen
selected targets against the provisional reference, at roughly 16.76 extra
seconds each. That supports bounded suggestions, not silent acceptance or
higher thinking on every page. Raw model difficulty is not calibrated certainty;
whole-capture review matters because omissions can be unflagged.

Warm KFD accounting was about 113.15 GiB / 121.5 decimal GB, with little extra
allocation for serial photos. KFD, GTT and RSS overlap; do not add them or treat
MemAvailable as safe spare GPU capacity. No power measurement is required.
The complete evidence is in `~/huion/journal-photos/2026-09-14/REPORT.md` and
`HALOGEN-RECIPE.md`; the new explicitly requested off confirmation is retained
separately under `runs/writer-confirmation-off`.

## Corrections are durable evidence

The authoritative annotation store is `/var/lib/handwriting-annotation`.
Writer saves append revisions; they never erase earlier readings. The literal
reading, intended spelling, line context, image evidence and handwriting notes
remain distinct. Model-assisted resolutions also append events with immutable
reference snapshots and an explicit actor. A model review cannot overwrite an
already resolved writer decision. Neither kind of review edits model weights.

Keep the full correction trail for future offline analysis. Visual example
packets currently require explicit writer approval of a selected crop and its
exact label; model-reviewed decisions alone do not meet that boundary. A
reopened decision or revoked reuse removes the example from future packets,
not from history. There were no approved visual examples after the first 26
passes; the corrections still remain useful evidence. Never silently turn a
provisional vocabulary or model consensus into a writer-labeled shape example.

Future adaptation should retrieve a small relevant subset of corrections or
approved examples, retain their revisions in the request record, and compare
outcomes on new pages. Do not stuff the entire growing log into every prompt.
The present photo trial does not establish that visual-example prompting improves
accuracy; that needs its own evaluation on actual Huion captures.

## Installed manual pilot

The packaged `handwriting-intake` command defaults to the managed state directory.
Its [command contract](../pkgs/handwriting-intake/README.md) gives the full workflow:

```sh
handwriting-intake receive ~/Paper/inbox/BATCH/page1-DD-MM.json
handwriting-intake run CAPTURE_ID --allow-unknown
handwriting-annotation --state /var/lib/handwriting-annotation import-items --items REVIEW_PACKET
# After whole-capture writer review on handwriting.internal:
handwriting-intake export CAPTURE_ID --review-state /var/lib/handwriting-annotation --output-dir ~/Paper/transcribed
```

Use the returned capture ID and review-packet path. This manual pilot performs no
inbox scan or automatic GPU request. The two daily backup timers cover the managed
annotation and intake stores. The intake backup also preserves the exact tracked
export files. A cross-package offline check verifies receive → OCR fixture →
annotation import → writer decision → literal export → both snapshots; it verifies
that model-assisted review cannot publish the whole capture. No synthetic writer
decisions are put into live state.

## Next real Huion trial

Device sync already delivers JSON/SVG/optional PNG to `~/Paper/inbox` via the
client spool and rsync retry timer. Keep this separate from `~/Paper/intake`,
which triggers printing. Existing calibration captures do not start daily use.

The first pilot should explicitly select one new received capture and run it
serially. Preserve received files. Current legacy exports do not record whether
the device page was complete; represent that as `unknown`, even when JSON/SVG
parse and files appear stable. A reviewed capture is not proof of complete
physical-page capture. Durable capture-side completion receipts are still needed
before unattended finalization. Never clear or delete device/source files from
the OCR consumer.

Require whole-capture writer review before exporting its literal transcription.
Keep each exported revision and its source/event provenance. Model-assisted
resolution of individual doubts cannot substitute for that first-pilot gate.
If a source, target export or writer revision changes underneath an operation,
stop that operation visibly instead of overwriting it.

After the first real capture has completed receive → OCR → review → export,
record its source and recipe identity as the start of ordinary use. Review
backlog/capture gaps after a week; ask Codex for an image-and-correction audit
within one to two weeks. Include original off answers, any retries, missing-line
corrections, writer/model review provenance, latency and memory observations.
No future Codex session has been scheduled automatically. The full commissioning
checklist is `~/huion/DAILY-OCR.md`.


## Verified preservation and deployment — September 14

The full `~/huion` workbench and `~/sept14-notepad` were archived at:

`/mnt/nas/documents/handwriting-workbench-archives/20260914T102604Z/`

`workbench-and-notebook.tar.gz` contains 3,064 files/links (453,632,183 compressed
bytes). Every archived file hash and symlink target was checked against its
source, and the source inventory remained unchanged throughout. `manifest.json`
records the inventory and archive SHA256
`dadd870c6fe161bcbdca3a669863ca038c5be082d4e85735e0a687d8119a3402`.
A Git bundle of the consolidated dotfiles branch is kept beside this archive.
This is an additional preserved snapshot; the original working folders remain.

The post-review annotation snapshot at
`/mnt/nas/documents/handwriting-annotation-backups/20260914T102302.910706463Z/`
contains 133 tasks and all 136 events, including the original 29 writer saves
and 107 model-assisted resolutions. All 121 manifest checksums were verified.
The new intake store was initialized empty, without importing calibration data,
and its initial managed NAS snapshot passed checksum and SQLite integrity checks.
Both daily backup timers and the annotation service are active.

The final coordinator configuration built successfully, with 18 annotation
backend tests and 13 intake/interface tests passing. Real Chrome checks covered
the menu, exhausted queues, save/reload/reopen history, deferred work and
multiline capture review in isolated state. The deployed menu returned
“133 reviewed · 0 remaining” with normal private TLS, on desktop and mobile
widths. No test annotations were added to the live writer record.

The manual command is installed; no automatic inbox-to-OCR dispatcher is running.
The first real Huion source/render/OCR/review/export trial remains the next
commissioning step, as requested. The current corrected journal is already in
`~/sept14-notepad`.

2026-09-20: ~/sept14-notepad has been landed into notes at references/continuity/2026-09-14-pickup/sept14-notepad/ (with PROVENANCE.md); the ~/huion source paths cited above now resolve under /mnt/nas/documents/archive/home-sweep-2026-09-18/rescue/huion/. The home copy is removed.
