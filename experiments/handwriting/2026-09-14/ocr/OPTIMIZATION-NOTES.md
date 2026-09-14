# OCR appliance: prompt caching, compilation and local escalation

Research snapshot, 2026-09-14. This records possible experiments; no new service,
optimizer, escalation policy, or fleet setting is installed.

The intended operating model is a resident Halogen appliance with a serial queue:
one page per request. Frontier models help review difficult evidence and develop
the recipe. The user is supplying further analysis before the design is finalized.

## What the Sunday research contributes

`~/sunday-qwen-optimization` contains research and proposed experiments, not an
implemented prompt optimizer. Its DSPy-style compilation discussion is explicitly
a primer: `findings/06-qwen-next-workerd.md:715`. Earlier llama.cpp/vLLM and dual-node
deployment details describe retired systems and should not be copied into Halogen.

Here, compilation can mean using corrected handwriting to select a compact prompt,
reference examples, preprocessing settings and inference flags against a held-out
validation set, then freezing that recipe. It does not imply weight fine-tuning,
another resident model, or new GPU kernels. No speedup from compilation is measured.

## Concrete cache experiment after the baseline

Actual Halogen 0.7.0 supports a snapshot boundary after the initial system message,
as well as history. See the captured frontend at
`runs/halogen-vanilla-2026-09-14/audit/serve_api.py:3139`.

The baseline deliberately has just one user message, containing the prompt and
image. It therefore has no separate static system snapshot. A subsequent A/B can
move stable transcription rules to a system message and keep the changing page in
the final user message. That changes the prompt, so preserve the vanilla results
and compare quality as well as timing. Short OCR rules may save little time; a
longer confirmed reference prefix might save more, but this must be measured.

Mode 2, in-place KV and eight LRU entries already run on the worker. Inspect
`/cache` and per-response `timings.cache_n`; do not assume an identical prefix was
reused. Mode 2 can alter numerics after reuse. Mode 1 only caches at chunk boundaries
(default 32768), so it does not provide useful caching of these small prompts.
`prompt_cache_key` is accepted but ignored on Responses; the prefix itself matters.

The initial six-page run reported zero reused tokens. The interleaved effort test
subsequently demonstrated actual cache reuse on several repeated images, including
across medium/off template variants. That proves token-state reuse occurred; it
does **not** prove image decoding or the vision tower was skipped. Keep image
processing, prefill and decoding costs distinct when measuring benefit.

The shipped `flash-tune.plan` already supplies kernel choices. Retuning with
`HALOGEN_MATMUL_ALGOS=8` needs a new persisted plan and representative workload;
no evidence here establishes an OCR benefit. It is separate from prompt compilation.

## Certainty and escalation, proposed rather than calibrated

Current Qwen answers already identify uncertain spans and alternatives. A later
structured response could attach `clear`, `uncertain`, or `unreadable` to regions,
with a best reading and alternatives. Validate the structure client-side; the
running engine has no constrained JSON decoding.

Do not interpret a self-reported numerical confidence as a calibrated probability.
Even alternatives can stay within the same mistaken reading: the p05 low-effort
answer offered `tedious` versus `tedious!`, while Astra's candidate was `been done`.
An uncertainty flag is useful routing evidence, not a guarantee of error detection.

The user's proposed first escalation stays local:

1. Process the original page with a fixed basic recipe.
2. Revisit flagged regions with a readable crop and page context.
3. Inspect selected **writer-confirmed** lookup-table examples; do not use candidate
   labels as established truth or force the target to match an example.
4. If still unresolved, queue human/frontier review with the original evidence and
   competing readings. No automatic cloud dispatch is installed by this experiment.

Calibrate routing against fresh, writer-corrected pages. Measure how many actual
errors are flagged and how many correct passages are unnecessarily escalated; check
a sample of unflagged pages for confident errors. Distinguish image readability
from word interpretation and preserve the initial reading before any guided retry.

Numbers/names, missing lines, truncation, invalid output and unreadable regions
can also trigger review independently of confidence. Agreement between two model
passes does not turn a label into ground truth. Final policy awaits the new journal
photos, writer corrections and the user's next analysis.
