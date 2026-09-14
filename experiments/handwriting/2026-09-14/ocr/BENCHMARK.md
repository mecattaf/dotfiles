# Halogen handwriting OCR: thinking levels and unified memory

Measured on worker, 2026-09-14. **Thinking disabled is the leading next-test
candidate for the serial OCR appliance.** It was much faster on these six pages,
without increasing aggregate disagreement with the provisional Astra transcript.
No deployment setting was changed. Final choice awaits real journal photos and
writer-confirmed labels.

## What was tested

Original six distinct Huion PNGs, 900 × 1190 each. No examples, lookup table,
stroke JSON, or existing transcription went into the requests. Temperature 0,
MTP, a 16384-token shared reasoning/output budget, and the same OCR instruction.
One page at a time. The running API and engine are Halogen Flash 0.7.0 with the
quality overlay and vision tower; [the audit](runs/halogen-vanilla-2026-09-14/AUDIT.md)
records the entire deployed path and effective flags.

The effort experiment ran 24 requests: one per page at low, medium, xhigh and
thinking off, rotating mode order by page. `minimal` is an alias for low, and
`high` aliases xhigh. These are not five independent effort levels.

| Setting | Six pages, seconds | Reasoning tokens | Word disagreements / 93 Astra words | Requests reusing cache |
| --- | ---: | ---: | ---: | ---: |
| Thinking off | 24.95 | 0 | 9 | 4 / 6 |
| Low | 71.25 | 1661 | 10 | 0 / 6 |
| Medium | 62.59 | 1551 | 10 | 2 / 6 |
| Xhigh | 76.65 | 2048 | 9 | 1 / 6 |

The original default-xhigh run took **82.84 seconds**, with no reported cache
reuse. A separate thinking-off repeat took **33.58 seconds**, with one of six
requests reusing cache. This repeat produced the same six transcripts as the
first off pass. Do not attribute every timing difference to thinking: cache state,
file-cache warmth and ordinary runtime variation differ. No cache was flushed and
the server was not restarted. These are small appliance-workload measurements,
not a latency distribution or an upstream framework comparison.

Word disagreement is exact Levenshtein distance after case folding and stripping
punctuation; it is **not accuracy**. Astra's initial readings are provisional and
its interactive prompt was not matched to the isolated Halogen request. The circle
rendered as `O` counts as one extra word. Case/punctuation-sensitive character
disagreements were 23/off, 26/low, 25/medium and 25/xhigh. Physical line breaks are
not scored. Mode rankings can change after correcting the reference.

Lower thinking did not monotonically reduce reasoning: low produced more thought
tokens than medium, and sometimes more than xhigh on individual pages. In this
template, effort changes an instruction, not a hard reasoning-token allowance.

Examples needing review: every setting read `ironically` where Astra read
`unironically`; xhigh read `has conclue`, and lower/off settings read `too tedious`,
where Astra read `has been done`. Off read `Show ... stuff` on p03, whereas the
thinking modes read `Shew ... sty`. Extra reasoning is not automatically a better
reading. Qwen flagged several of these regions itself, but its alternatives were
not always useful. [Escalation notes](OPTIMIZATION-NOTES.md) keep the first retry
local: crop and inspect confirmed handwriting references before frontier review.

## Unified-memory footprint: the 110 GB question

**The live KFD counter reports 112.31 GiB (120.59 decimal GB) of GPU-accessible
system memory in use with the model resident.** Halogen was the only KFD process.
That supports “roughly 110” if GiB was meant; it is larger than 110 decimal GB.

| Counter | Idle with model loaded | Interpretation |
| --- | ---: | --- |
| KFD system memory | 112.31 GiB | Broad GPU allocation/registration accounting, including host user-pointer memory |
| AMD-SMI compute-process memory | 42.45 GiB | Narrower compute allocation view; omits much of registered host-memory footprint |
| Driver total GTT used | 42.48 GiB | Device-wide GTT allocation, stable throughout ordinary-page OCR |
| Engine process RSS | 70.27 GiB | Resident mappings, largely checkpoint files; overlaps the broader accounting |
| API frontend RSS | 0.28 GiB | Python/image-processing process |

These are **overlapping views and must not be summed**. The KFD figure is driver
accounting, not an independent physical-page census. Its live output was
`System mem used 115001M` and `TTM mem used 43477M`; despite the `M` label the kernel
prints bytes shifted by 20, i.e. MiB. KFD accounts GTT and registered user-pointer
memory in the system total, while only the former contributes to its TTM total.
See the [kernel implementation](https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/amd/amdgpu/amdgpu_amdkfd_gpuvm.c).

The engine's startup log had an earlier 103.7 GiB subtotal: 68.0 GiB locked base
and overlay weights, 14.4 GiB KV pool and 21.3 GiB working memory. That is an earlier
engine subtotal with different coverage, not the later live driver-accounted
footprint. The vision tower also loads 0.84 GiB of resident weights. Use the live
112.31 GiB figure for planning this running instance rather than adding estimates
to the startup subtotal.

## Additional cost of one page

Read-only telemetry sampled GPU busy, GTT/VRAM, engine RSS and later frontend RSS
and KFD counters every 250 ms. Each run began with ten seconds of idle measurement,
with the model already loaded. This is incremental cost over a warmed resident
appliance, not startup or first-ever vision allocation.

| Input | GPU-accounted memory increase over idle | Other observations |
| --- | ---: | --- |
| Original 900 × 1190 pages | 0 GTT increase; KFD at most 1 MiB in the repeat | Engine RSS rose at most 53.5 MiB across the six-page repeat; frontend RSS stayed flat |
| Large page render, 1800 × 2380 | Peak **+839 MiB KFD = 0.82 GiB**, including **+828 MiB GTT** | Engine RSS peak +73.6 MiB and frontend +13.3 MiB relative to the pre-repeat idle baseline; do not add these to KFD blindly |

The large input exercised near the configured vision processing ceiling: the
frontend resized it to **1664 × 2176**, yielding 3536 image tokens and a 3675-token
prompt in off mode. Its single request took 18.21 seconds and reported no cache
reuse. This is a high-resolution **stroke render used as a memory probe**, not a
phone photograph or a journal-photo accuracy result.

Peak broad KFD accounting reached approximately **113.12 GiB**. Immediately after
the large request it still reported 115834 MiB (about 113.12 GiB), so most of the
larger working allocation remained resident. Treat approximately **1 GiB beyond
the measured base** as this observed single-large-page working allowance. It is
not a claim that each subsequent page adds another GiB, nor a guarantee for arbitrary
image sizes, multi-image prompts, more references, longer output, or concurrent jobs.
No long-duration accumulation test was performed.

The KV pool is already allocated for the resident server. Reserving prompt plus
output-budget positions for one request consumes capacity inside that pool; it does
not allocate a fresh full pool per page. Lower thinking mainly reduced **GPU busy
time**, not the resident model or pool memory. GPU busy averaged approximately
94–98% within the measured request windows, peaking at 100%; idle was 0%.

## What remains for other processes

The host reports **125.09 GiB of system RAM**. Subtracting the large-page peak KFD
accounting leaves about **12 GiB before OS, frontend, other processes and file-cache
needs**. That is gross headroom, not an allocation guarantee. No stress allocation
was attempted. Keep the worker's other workloads modest until measured together.

`MemAvailable` reported roughly 78 GiB during these tests, which is misleading for
this purpose: the server documents that registered/pinned checkpoint pages can
still be classified as reclaimable file cache. Its startup log explicitly warns
about that discrepancy, and `Mlocked` was zero despite the engine's confirmed
weight registration. The 47.7 GiB on-disk N-gram lookup table also benefits from
the remaining file cache. GPU utilization returning to zero does not unload weights.

## Evidence and reproduction

- [Original default run](runs/halogen-vanilla-2026-09-14/COMPARISON.md), including
  verified Astra provenance, raw requests, answers, timings and health.
- [24-request effort summary](runs/halogen-efforts-2026-09-14/summary.json) and
  its per-mode folders; every request's flags, source hash and response are retained.
- [Memory repeat and large-image summary](runs/halogen-off-memory-2026-09-14/summary.json),
  plus timestamped `memory-samples.jsonl` in that directory.
- [KFD snapshot](runs/halogen-efforts-2026-09-14/memory-audit/kfd-memory-limit.txt),
  [AMD-SMI](runs/halogen-efforts-2026-09-14/memory-audit/amd-smi-process.json),
  and [engine RSS/PSS](runs/halogen-efforts-2026-09-14/memory-audit/engine-smaps-rollup.txt).

Run `python3 effort_benchmark.py NEW_DIRECTORY` for the four-mode serial test;
`--modes off --large-probe` repeats six pages plus the large render. It uses a
bounded read-only worker sampler, stopped at completion. `summarize_efforts.py`
computes metrics from saved responses and samples. All 31 measured requests
(24 + 7), and the six earlier vanilla requests, completed normally. No worker
services, engine flags, model loans or deployment configuration were changed.
