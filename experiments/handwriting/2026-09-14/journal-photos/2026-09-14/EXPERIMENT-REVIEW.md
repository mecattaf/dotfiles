# Experiment review

Reviewed `experiment/benchmark.py`, `correct.py`, `correction_tasks.py`, the worker memory sampler, and runtime-summary compatibility. This is a disposable handwriting experiment, not a deployed OCR service. No inference was run and the ongoing baseline process was not modified during this review.

The experiment supports a useful within-collection comparison. Its final accuracy claims must remain relative to the visually reviewed Codex reference, which is not writer-confirmed ground truth. Seventeen photographs represent twelve physical pages; deliberate overlaps are useful reconstruction evidence, not independent additional pages.

## Changes made before correction inference

- Correction inputs now require a matching frozen development-vocabulary SHA256, at most three hints drawn from that vocabulary with matching development provenance, the correct development/held-out partition, one task per capture, and explicit visual location verification. A validated task document must retain the top-level `vocabulary_sha256` from `tasks-proposed.json`.
- The baseline gate checks every expected mode/capture metadata file, rather than accepting any arbitrary collection of 68 files. Complete response status and successful structured parsing remain separate observations.
- Correction responses receive strict field/type checks, including string alternatives, their maximum count, nonempty clear readings, and null readings for absent targets. A well-formed self-report remains a proposal, not an acceptance criterion.
- In-flight correction metadata is saved before inference. Transport failures retain timing windows and error metadata. If a correction cell needs a retry, its prior request, response, parsed output, answer and metadata are archived under that arm's `attempts/` directory before replacement. Failed `/cache` reads after a response no longer discard an otherwise obtained answer.
- The correction protocol records selected arms and actual thinking settings. Arm rotation is described accurately as rotation by eligible-target index. Responses remain serial; there is no batching of multiple pages into one request.
- The correction sampler code is retained with the run. Sampler freshness is checked at request boundaries and after the final idle interval; unexpected sampler failure stops further requests while preserving completed response evidence.
- Selection output now records coverage for every photograph: no parsed off result, no eligible self-reported span, a selected span crossing lines, or a proposed crop. This does not change the frozen selection/ranking rule. The crop override mechanism is preserved.
- The runtime summarizer recognizes both `idle-*.json` and `final-idle-*.json`; previously the correction runner's final-idle name was missed.

Five offline checks passed: correction schema rejection, vocabulary/partition/location isolation, retry evidence preservation, exclusion of cancelled hard spans, and final-idle recognition with memory-window matching. These checks make no model requests.

## Baseline limitations retained without disturbing the running sweep

The baseline correctly preserves full obtained responses, request settings, image hashes, reasoning/output usage, cache counters, and per-request clocks. Its mode order rotates across captures and requests run one at a time. It does not provide a cross-client fleet lock; health checks cannot exclude another client arriving after the check.

An interrupted baseline request can lack metadata because baseline metadata is saved only after a response and subsequent cache read. A resumed incomplete cell can overwrite earlier evidence, and a stale parsed file may survive a failed subsequent parse. If interruption occurs, preserve the affected run artifacts before retrying and only score parsed results whose corresponding metadata says `parsed=true`. Do not infer that a missing metadata file consumed no GPU time.

The baseline protocol does not pin the complete input-manifest hash. Per-request image hashes retain what was actually submitted, but changing the manifest or images between resumptions could mix inputs under one output directory. Keep them frozen for this run.

The baseline has no explicit post-run idle interval; its last sample must not be described as idle. It starts a four-hour sampler and checks initial readiness, but does not subsequently check sampler liveness. Verify coverage/sample counts in the final runtime report. The correction runner adds a sampled ten-second final idle window and sampler checks.

## Interpretation constraints

**Development split:** photos 01–08 comprise physical pages 1–6; held-out photos 09–17 comprise pages 7–12. There is no same-physical-page overlap across that boundary in the input manifest. Vocabulary comes exclusively from development references. Development-target results are potentially helped by vocabulary derived from the very page being corrected; use held-out results for the correction claim. Crops may be visually repositioned only to include the selected span, not to replace a hard target with a known reference error.

**Selection:** one eligible, uniquely occurring, self-reported span is selected per photograph. Hard/unreadable reports outrank ordinary uncertainty, explicit cancelled spans are excluded, and lexical hints contribute to ranking. This tests targeted recovery, not detection of every wrong word. Confidently wrong words may receive no correction at all. “Clear,” “uncertain” and “unreadable” are model reports, not calibrated probabilities. Coverage records are part of the denominator.

**Correction arms:** `off-crop`, `off-crop-hints`, `low-crop-hints`, and `medium-crop-hints` share the same selected target and crop. When there are no vocabulary candidates, the first two arms carry identical prompt content; they do not estimate a vocabulary benefit on that target. There is no high-thinking crop arm and no no-crop retry control. This design can compare the selected practical recipes, but cannot isolate every cause of improvement.

**Runtime/cache:** stable system prefixes and deployment cache state are retained. A single observation per cell, rotated ordering, and `cache_n` reporting do not remove warm-cache or time-order effects. Runtime includes request construction/transport and a pre-request cache probe, whereas server token timings describe narrower phases. Completion budgets include thinking. Latency is operational evidence from this run, not a universal throughput guarantee.

**Memory:** KFD system, KFD TTM, GTT, VRAM, process RSS and host memory are overlapping accounting views; never sum them. Engine/frontend RSS sums within each process category can also include shared mappings. Report decimal GB and binary GiB explicitly. Starting idle is a warm, already loaded appliance after earlier OCR work, not a fresh model-load measurement. Thus idle-to-peak is the observed extra cost above that warm state, not a clean attribution of all model/prompt/image allocations from zero. Host `MemAvailable` includes reclaimable mappings and is not a safe additional-GPU-allocation budget.

The sampler polls approximately every 250 ms. Timestamp matching uses coordinator receive-monotonic time, so SSH scheduling and delivery can blur short peaks around request boundaries. Maxima in different metric rows need not occur together. Correction reports should pass `--expected` equal to four times the number of validated targets, rather than leaving the baseline default of 68.

## Subsequent hardening for future baseline/fresh-off runs

Before changing `benchmark.py`, its exact prior contents were copied to `runs/baseline/benchmark-source.py`; SHA256 is `5322820a7ffaeeaa6bb3492193927be9dd0caaa876bd97bc10b4ec7713cf0a7c`, also saved in `benchmark-source.sha256`. That snapshot records the code already loaded by the ongoing 68-cell baseline. No process was interrupted or restarted. The preceding baseline limitations describe that running version.

Future invocations now save their own source snapshot and invocation metadata (selected captures/modes and manifest SHA256). Completed-cell resume checks require the same request settings, system/user prompts, image hash and encoding, together with retained response/parsed evidence. Incomplete retries archive all prior cell artifacts, including stale parsed files. In-flight request windows are saved before inference; transport or malformed-response failures retain explicit failure metadata. A failed post-response cache probe no longer discards an obtained response. Missing sampler output is detected at request boundaries, and successful future runs include an explicit sampled ten-second final idle interval plus sampler status.

The OCR system prompt, user prompt, thinking settings, temperature, MTP setting, token limit and rotating capture/mode order remain unchanged. These robustness changes therefore also apply to the planned `runs/fresh-off` confirmation without changing its OCR recipe. Six offline guard tests now pass, including baseline timeout bookkeeping, changed-image resume rejection and preservation of stale parsed output in an attempt archive.

## Bounded native-resolution tile probe

`experiment/tile_probe.py` freezes `tile-protocol.json` by default and makes no request without the orchestrator's explicit `--run`. The rule was frozen before held-out selection: choose the largest successful off-output normalized word count independently in development01–08 and heldout09–17, with capture order breaking ties. Selection waits for all17 successful off outputs and never reads reference errors. It persists selection before copying the two reviewed references for identical before/after scoring.

Each chosen original photograph is decoded upright at native resolution using the verified input-manifest rotation (including capture06's zero rotation). The upper tile covers0–60% of image height and lower tile40–100%, retaining20% full-height overlap. Tiles use the existing Halogen max-area/32-stride BICUBIC convention. The two photographed pages produce four serial requests with the exact baseline system/user prompt and off-mode settings. The probe uses its own inputs/evidence under `runs/tile-probe`; baseline files are read-only. It records initial/final sampled idle windows and per-tile runtime/cache/memory metadata.

Automatic stitching needs at least ten contiguous normalized matching words, restricted to the lower token half of the upper response and upper token half of the lower response. Competing positional offsets or a tied longest anchor cause refusal; both original tile texts and candidate anchors are retained. Accepted stitches preserve source text around the splice and are proposals for review, never automatic notebook replacement. The scorer reports one-call baseline cost beside two-call tile cost and evaluates both against the same frozen reference copy. Two selected probes cannot establish generalization across the handwriting collection.

Four offline probe tests passed: partitioned word-count selection and tie behavior, original orientation/native bounds/overlap/stride/area, exact overlap removal without losing punctuation/line breaks, and refusal of missing or repeated ambiguous anchors. No tile inference was started during implementation.

Commands, once data is ready:

```bash
python experiment/tile_probe.py --prepare  # offline; requires17 complete parsed off outputs
python experiment/tile_probe.py --run      # orchestrator only, after its other sweeps; gates all68 baseline cells
python experiment/tile_probe.py --report   # offline regeneration from saved tile responses
```
