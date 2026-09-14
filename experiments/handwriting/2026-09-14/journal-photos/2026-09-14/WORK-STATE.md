# Handwriting work state — 2026-09-14 source-archive snapshot

This is a historical checkpoint while intake implementation and deployment work continue. Canonical current status belongs in `~/mecattaf/dotfiles/docs/handwriting-intake.md`.

## Completed

- 17 phone photos reconstructed into 12 physical pages; originals, sequence, all model readings and frozen Codex reference hashes preserved.
- All 174 Halogen attempts finished: 68 baseline, 17 first fresh-off, 68 correction, four tile calls, 17 newly requested writer-era off confirmations. One original correction response rejected by schema; no hidden retry.
- Latest no-thinking pass: 406.51 seconds total, 23.91 seconds/photo; all 17 answers byte-identical to the first fresh-off pass, zero reasoning tokens, no hints or writer labels in requests. KFD113.157 GiB /121.502 GB, no sampled allocation growth over idle. Worker returned idle; sampler stopped.
- Claude first-reading comparison complete; no Claude cross-review claimed. 26 priority tasks plus 107 separate Qwen flags preserved.
- Writer finished all 26 priority items: 24 resolved and two unreadable. Ten literal changes applied to `~/sept14-notepad/page1.md` through `page12.md`, plus 14 unchanged confirmations recorded with an immutable application receipt. The two writer-marked unreadable locations remain explicit; this is not full-page writer ground truth.
- `https://handwriting.internal` live through NAS DNS and coordinator Caddy/service. Persistent state `/var/lib/handwriting-annotation`; append-only review events and evidence; consistent daily NAS backups. Initial deployment is dotfiles commit `194d2d9f`; later UI/intake revisions are in progress.
- Initial 14 backend tests, disposable browser checks and 41 experiment tests passed. These counts describe initial verification; subsequent schema/intake tests are underway separately. No synthetic writer events were created in production.

## Current work boundary

The user explicitly authorized model-assisted resolution of the 107 Qwen flags. Reconciliation produced 101 resolved and six unreadable model reviews, all imported: `model-review/import-receipt.json` records 107 saved and zero rejected. The app now has 125 resolved, eight unreadable and zero pending tasks, with provenance split between 26 writer decisions and 107 model reviews. Seven unique uncertain inscriptions remain because the margin appears in duplicate tasks. One additional model-verified literal notebook correction, hygiene → higiene, is separate from the ten writer changes. Model reviews retain distinct actor/provenance and are not writer labels or approved examples. Preserve all existing writer revisions.

The user also authorized merging the implementation and experimental source into canonical dotfiles. The source/methodology snapshot lives in `experiments/handwriting/2026-09-14`; full workbench and notebook evidence are being separately archived to the NAS. Neither a source archive nor a model-review proposal proves a successful runtime import or backup; use the corresponding final receipts.

Real Huion input is the next test. Intake implementation and tests are underway; capture-completeness receipts, first-real-page evidence and the 1–2-week audit boundary must be checked in the final commissioning docs. Do not count these photographed or legacy calibration samples as Day1. No future Codex session is automatically scheduled.

Preferred measured first pass: whole-page thinking explicitly off. A bounded low-thinking crop retry with relevant hints remains reviewable (+16.76 seconds mean in this experiment). Unreadable items and omissions still need attention; self-reported confidence is not calibrated. No Halogen restart, alternate model, NPU or weight training is required.

Full measurements, provenance and limitations: `REPORT.md` and `runs/writer-confirmation-off/CONFIRMATION.md`.
