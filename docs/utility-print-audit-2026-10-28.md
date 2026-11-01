# Utility calls and printing, 28 October 2026

The recurring print failure has three separate causes. October 24 JSONL
tracebacks show Markdown rendering successfully and then crashing at submission:
`decision.pdf` is an output path, while the PDF-drop branch writes a metadata
object under that same key. October 26–27 records also show the migrated NAS
daemon lacking Chrome and CUPS. Historical requests using the retired Halogen
model ID fell back to deterministic typesetting; that failure did not cause the
submission type error. DSH is not involved in these utility HTTP requests.

The existing fix is [PR 635](https://github.com/mecattaf/dotfiles/pull/635),
verified at `3e4be2d7ff5861db56c3842c8c9a909731ad24b8` before this audit.
It keeps source files, queue state and printer receipts on NAS, packages
Chromium/fonts/Gufo for request-scoped rendering on compute, and fixes Markdown
submission. Its October 26 physical qualification reported IPP job 424 completed
with one impression. That proves the qualified package path, not NAS activation.

This follow-up closes remaining utility integration gaps:

- One `utility-model` package supplies the system client, print renderer and
  monthly evidence reviewer. The stable application ID is `utility`; its sole
  upstream is Gufo's `qwen3.8-flash-next` at `http://strix-coordinator:8731`.
- The installed monthly reviewer no longer pulls in Pi, copies Pi model/session
  state, or requires a nested Tally job. Its no-tools judgment goes directly
  through the utility seam. It records the request and response, validates the
  declared provider/model/endpoint, bounds input and output, and rejects
  truncated or malformed commentary before publication.
- The monthly supervisor checks compute disk space before each Nix build. Its
  scheduler is external; this change creates no timer or recurring routine.
- Print rendering rejects the dormant worker, and the NAS daemon includes
  `/run/wrappers/bin` for its existing sudo queue inspection/repair commands.

Other utility consumers were checked: academic OCR, handwriting intake and call
cleanup already use the current model. OCR embeddings require an explicitly
provided independent server and are skipped when absent; they do not call Gufo
as an embeddings service. The prior provider-cutover table remains historical.

Validation ran on `strix-coordinator`, with runtime-sensitive tests under
`runtime-test`: 93 print cases, 11 utility cases, the monthly package's fixture
workflow, package builds, and `print-paper`, `print-plane` and `utility-model`
Nix checks. A synthetic built renderer also reached real Gufo and Chromium,
returning GPU provenance, one A4 page and a passing exact one-page gate. No
physical print was submitted by this audit. The monthly package closure contains
the utility client and no Pi or Tally package.

The bounded archive reread includes the actual October 24, 26 and 27 failures,
recovery attempts and receipts, plus the October 22 sweep's archived JSONL
object. Exact private source paths, line numbers and per-line hashes remain in
the local audit ledger, outside Git. This audit is not another exhaustive
semantic review of all chats.

Deployment order is compute's renderer first, then NAS CUPS/remote-render units.
Keep historical failures: several were already printed by manual workarounds,
so replaying the failed directory would produce duplicate copies. No live jobs,
Herdr sessions or user managers were restarted during this work.
