# strix-halo community digest — deep-pass baseline + delta-refresh protocol

Captured 2026-07-11. Operational companion to `strix-halo-llm.md` (the living-device
doctrine + watch list + specialized lanes — read that first; this doc is the deep-pass
it calls for). One full read of every watch-list repo was done today against pinned
HEADs; this doc records what each repo is, what it found, what transfers to the fleet,
and exactly how to read only the *delta* next sweep. Durable reference — findings are
dated, pins are recorded, nothing here is a task list.

Local clones (blob-filtered, full history): `~/Downloads/local-ai-june11-references/`,
baseline manifest `MANIFEST.json` in that directory.

## 1. Production truth — what is actually running (2026-07-11)

The line between HAVE and PLANNED, stated once so no later reader confuses the two:

**Running today:**

- **tally v0.1.0 daemon + two `pls` brokers** on the coordinator — the queue/lease
  substrate is live (spec + CLI: `github.com/mecattaf/tally` `docs/`).
- **asr-rs** — Tom's active workstream: CPU-only streaming STT on the coordinator
  (dual-Parakeet, fp32 ONNX, branch `v2-parakeet`). Never takes a GPU lease by design.
- **The daily academic-sidecar OCR drain** — the ~4.7k paper sidecars drain daily, but
  today that drain is **manual/supervised**. The Qwen3-VL suite that will own it
  (8B fast pass + 32B refine + Embedding-8B, ~35 GB resident — loadout rows 9–10, spec
  in `github.com/mecattaf/academic-rag`) is **NOT yet stood up on the worker**.

**Not running — nothing else is:**

- **NO local model servers are currently live.** No llama-server, no kyuz0 toolbox
  container resident, no vLLM, no ds4, no voice stack, no NPU workload. Every model in
  the loadout plan's 10-row inventory except row 1 (asr-rs) is planned, not deployed.
- Everything in §3 below marked "applies now" means *transfers when we stand the lane
  up* — it is community knowledge banked against the P0–P7 phases, not a description
  of our boxes.

## 2. Deliberation log — where each ruling lives

A log of what was deliberated and *where*, not a re-statement. Latest is authoritative
for operational truth; earliest is canonical for lineage.

| Date | What | Where |
|---|---|---|
| 2026-07-06 | The 10-row loadout, TB3 topology, NixOS-vs-kyuz0 protocol table, phases P0–P7 — and **§6: twelve Tom rulings still pending** (kernel-param alignment, heretic picks, TTS engine, judge stage, two-box tally mapping, ...) | `mecattaf/notes` → `inbox/local-llm-loadout-plan.md` |
| 2026-07-06 | Decensored/abliterated pool — parked as-is per Tom's ruling (consolidation groups 6–7) | `mecattaf/notes` → `inbox/local-decensored.md` |
| 2026-07-07 | Transcription + diarization candidate comparison (VibeVoice-ASR-7B vs MOSS vs WhisperX vs FunASR) | `mecattaf/notes` → `inbox/july7-url-cleanup/transcription-dialarization.md` |
| 2026-06-23→ | tally paradigm — queue/lease/witness, Seam A admission, spec crystallized into the repo (work from the repo, not the closed notes deliberation) | `github.com/mecattaf/tally` → `docs/` (`SPEC.md`, `DECISIONS.md`, `CLI-SURFACE.md`) |
| 2026-07-05 | ds4 dual-node runbook — the both-GPUs-exclusive job class, exact run commands | `migration-journal/ds4-dual-node-lessons.md` (this directory) |
| 2026-07-11 | Living-device doctrine, community watch list, specialized lanes | `strix-halo-llm.md` (this directory) |
| 2026-07-11 | Deep-pass baseline of all watch-list repos + pinned SHAs | this doc + `~/Downloads/local-ai-june11-references/MANIFEST.json` |

One watch-list open item from `strix-halo-llm.md` §2 is now **partially resolved**:
lab.ciru.ai still has no dedicated public repo (live dashboard, likely tailnet-served),
but the GitHub org behind it was located — **`ciru-ai`** — and its `benchmarks` repo is
the source of the main llm.ciru.ai site (§3.15). Sweep the org, not just the site.

## 3. Per-repo digest

Grouped: field-notes/guides (3.1–3.3), the kyuz0 ecosystem — serving, voice, agents,
gen, training, base layers, ds4 (3.4–3.14), the ciru-ai lane (3.15–3.16). "Applies now" = transfers
to the fleet when the relevant lane stands up (see §1 caveat). All numbers are the
upstream authors' measurements on their own gfx1151 boxes, not ours.

### 3.1 sypherin/strix-halo-setup — a live box's field notes

- **Purpose**: single-operator living README of one continuously-updated Strix Halo
  box — systemd units, llama.cpp Vulkan/ROCm serving, kyuz0 toolboxes, OCR VLMs,
  ComfyUI, NPU (XDNA2) driver build. Content is rewritten to match whatever runs on
  the box that week.
- **Rhythm**: README rewritten wholesale nearly every commit ("sync to live box"),
  every few days–weeks; new topics get their own `docs/<topic>.md`.
- **Latest (2026-07-10)**: primary model Qwen3.6-35B-A3B-MTP GGUF with *native MTP
  speculative decoding* (`--spec-type draft-mtp --spec-draft-n-max 3`) — ~75–86 t/s vs
  ~61 t/s without; a classic separate draft model backfired (27 t/s, 20% acceptance).
  Claude Code runs fully offline via claude-code-router → llama-server. mmap policy is
  now **per-backend**: Vulkan wants `--mmap`, ALL ROCm toolboxes mandatorily
  `--no-mmap` (ROCm mmap >64 GB is very slow on gfx1151). FP8 is broken on gfx1151 for
  image/video gen — BF16 or GGUF only. NPU validated at 51 TOPS via out-of-tree
  xdna-driver build.
- **Applies now**: the `strix-llm-switch.sh` pattern (single source-of-truth unit file
  a watchdog reads) maps onto tally's job-to-unit binding; the MTP flags are worth
  testing on any coding model served for the pi harness; the ROCm-vs-Vulkan mmap split
  belongs in any NixOS wrapper we write; their `llama-surya2` OCR service is far below
  our academic-OCR bar (confirms §5).
- **Not covered**: serious academic OCR, diarization, streaming STT, video editing,
  deterministic builds, any scheduler (manual switch script only). Fedora-family paths
  — translate, don't copy.

### 3.2 boxwrench/tesla_agent — teaching guide + reproducibility ledger

- **Purpose**: CC BY-NC teaching guide + benchmark ledger for local *agentic* LLM
  workflows on Strix Halo, aimed at water-treatment operators; pinned llama.cpp tags,
  model checksums, blind pairwise quality evals.
- **Rhythm**: near-daily small commits into a dated "Unreleased" CHANGELOG;
  `reference/reproducibility-matrix.md` is canonical, README/dashboard are mirrors.
- **Latest (2026-06 stable ladder)**: code default Qwen3.6-35B-A3B MXFP4 (~58.5 t/s
  Vulkan, +13–19% over ROCm); quality champion Step-3.7-Flash + MTP draft (27.9 t/s,
  89% acceptance); Gemma 4 26B-A4B **QAT** Q4_0 + QAT-*matched* MTP head hits 71.4 t/s
  at 91.8% acceptance (mismatched head: 56.9% — head-matching is the whole gap). The
  hyped Qwen3.6-27B dense lost blind pairwise 0–6 and is explicitly not in their stack.
  Their SWaT real-data eval found the 35B agent out-reasoning the human answer key.
- **Applies now**: MTP self-speculative flags for any MoE with a `-MTP` GGUF; the
  **Nonce Gate** (agent must fire a real tool call and echo a random nonce — catches
  markdown-faked tool calls) is a cheap tally/pi sanity job; hard warning that
  `--reasoning-budget` capping breaks *stateful multi-step* agent loops (fine for
  single-shot) — carry into tally job design.
- **Not covered**: all five §5 lanes, multi-node orchestration, NPU. Non-commercial
  license; narrow domain.

### 3.3 hogeheer499-commits/strix-halo-guide — the benchmark log

- **Purpose**: evidence-driven, near-daily re-benchmarked reference for LLMs on Strix
  Halo; every headline claim backed by raw CSV/logs under `data/raw/<date>/`;
  increasingly folds in community reproductions (this is where `COMMUNITY_RESULTS.md`
  from the watch list lives).
- **Rhythm**: 1 commit every 1–3 days; each finding = raw-data dir + CSV row + prose
  update + regenerated chart.
- **Latest (→2026-07-10)**: Qwen3-Coder-30B-A3B Q4_K_S at ~101 t/s tg128 on official
  Vulkan release binaries (no build step needed); Gemma-4-26B QAT + matched MTP head up
  to 110 t/s — their strongest server route; **MoE concurrency cliff**: stock Vulkan
  llama-server drops 214→143 t/s aggregate going 8→9 parallel slots (upstream #25356)
  while Lemonade ROCm has no cliff; Ollama needs `OLLAMA_IGPU_ENABLE=1` or the iGPU is
  dropped; RPC rule of thumb — 2-node loses 14–22% tg128 on fits-on-one-box models,
  shard only for capacity; USB4 cluster tuning (MTU 9000, `pm_qos_resume_latency_us=100`
  → RTT ~134 µs) transfers directly to our TB3 link.
- **Applies now**: the >8-slot cliff is a hard ceiling for tally fan-out on one box;
  the RPC capacity-not-speed rule matches our ds4-only dual-node stance; pinned
  release-binary-over-source pattern is worth mirroring in nix packaging.
- **Not covered**: all five §5 lanes; Ubuntu-only setup script; no agent-harness or
  scheduler content.

### 3.4 kyuz0/amd-strix-halo-toolboxes — the serving substrate

- **Purpose**: THE toolbox images our serving protocol is ported from — pre-built
  llama.cpp containers across ROCm 6.4.4/7.2.4/nightlies and Vulkan RADV/AMDVLK, plus
  benchmark suite, GGUF VRAM estimator, distributed-RPC launcher.
- **Rhythm**: near-daily; rebuilds auto-trigger on upstream llama.cpp master changes
  (`poll-llama-cpp.yaml`) — the publish trigger is CI, not a human.
- **Latest (310c852, 2026-07-11)**: stable config = kernel ≥6.18.4 (older has gfx1151
  bugs), **linux-firmware 20251125 explicitly broken** (recalled, still shipped by some
  distros); boot params `amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856`
  (amd_iommu=off now beats iommu=pt by 5–12%, issue #66); hard requirement `-fa 1
  --no-mmap` on this hardware; MTP merged into llama.cpp master (old `-mtp` variants
  deprecated); rocm7-nightlies currently has a 64 GB memory-cap bug — avoid for large
  models; `llama-server --models-preset models.ini` router mode hot-swaps models in one
  process.
- **Applies now**: kernel/firmware pins feed the loadout §6 kernel-param ruling
  directly; `gguf-vram-estimator.py` is a ready-made tally pre-flight check before any
  model-load job; the models.ini router is an alternative to per-model units worth a
  ruling; per-model KV-cache quant defaults (q8_0 default, q4_0 for very large MoE) are
  a memory lever for tally job configs.
- **Not covered**: all five §5 lanes; no scheduler beyond the single-node router; no
  agent harness; Fedora-shaped (our NixOS port table lives in the loadout plan §3).

### 3.5 kyuz0/amd-strix-halo-voice-toolbox — the TTS lane's image

- **Purpose**: single-purpose image: Microsoft VibeVoice TTS/voice-cloning on ROCm
  gfx1151. This is the image loadout row 3 names.
- **Rhythm**: bursty, 14 commits total; manual workflow_dispatch builds; watch for
  torch/ROCm-nightly bumps and segfault fixes, not a cadence.
- **Latest (ab13312)**: Fedora 42 + TheRock gfx1151 nightly wheels; flash-attention
  built via Triton AMD backend; VibeVoice from kyuz0's own fork, weights from the
  community mirror `aoi-ot/VibeVoice-Large` (Microsoft retracted the originals — the
  mirror-fetch ruling in loadout §6 now has a concrete pointer). Root-caused the
  librosa→numba→llvmlite-vs-ROCm-libLLVM segfault; ships a numba shim +
  `NUMBA_DISABLE_JIT=1 LIBROSA_DISABLE_NUMBA=1`. Gotcha: wrapper's default
  `--model_path` is `/mnt/storage/VibeVoice-Large/`, contradicting the README's $HOME
  path — always pass it explicitly when scripted.
- **Applies now**: the numba/llvmlite fix applies to ANY librosa-touching audio
  pipeline in a ROCm toolbox (diarization lane included); the
  `_rocm_sdk_core`-derived Triton env detection is reusable for any Triton-on-ROCm
  workload; `refresh_toolbox.sh`'s skopeo-digest-diff pattern is a clean template for
  tally-scheduled toolbox refresh jobs.
- **Not covered**: ASR/diarization (this is TTS only), everything else in §5. No
  benchmarks or quality numbers at all.

### 3.6 kyuz0/local-agent-builder — harness patterns to mine

- **Purpose**: a coding-assistant Skill that scaffolds local-LLM agent apps
  (Textual TUI, Microsoft agent-framework, OpenAI-compatible endpoint). Per the
  doctrine doc: we mine the *patterns*; the ruling is pi harness directly, not this.
- **Rhythm**: low-velocity structural commits; no results/benchmarks ever published.
- **Latest (e5b0489)**: tool-quota system (`with_quota`, global per-tool call budgets,
  `QuotaAbortException` to hard-stop loop-stuck small models); delegation enforced by
  *disjoint tool lists* per tier, not prompting; headless mode with
  `required_artifact` (run fails unless a named file exists at exit); SRT shell
  sandbox (env whitelist, network-domain allowlist, secret-glob denylist); design
  constraint stated in their AGENTS.md: everything must assume 7–32B local models.
- **Applies now**: quotas as runaway-loop guards for any headlessly-supervised local
  agent; `required_artifact` is exactly tally's witness-completion shape — an agent
  job's success gate is a named artifact; the SRT sandbox recipe is the reference if an
  agent ever drives shell/builds inside a toolbox.
- **Not covered**: all five §5 lanes (only generic markitdown/liteparse for RAG
  ingestion).

### 3.7 kyuz0/deep-research-agent — the worked example

- **Purpose**: the pattern from 3.6 instantiated: strict Orchestrator→Searcher→Analyzer
  delegation chain against a local llama.cpp endpoint, each tier's context kept small
  by tool withholding.
- **Rhythm**: brand-new, 3 commits — treat any future check as a full re-read.
- **Latest (75671f5)**: leaf Analyzer has no web and no delegate tool at all; PDF fetch
  sniffs magic bytes (`%PDF`) instead of trusting Content-Type, then
  **liteparse-first / markitdown-fallback** extraction; ddgs client needs a
  lock + engine pre-warm to avoid PyO3 deadlocks under concurrency; `eval/` is a real
  resumable LLM-judge harness whose dataset includes ground-truth specs for our own
  hardware class (Ryzen AI Max+ 395: 40 CU RDNA 3.5, 59.4 TFLOPS BF16, 256 GB/s).
- **Applies now**: the eval harness is a ready template for A/B-ing local model/quant
  configs as tally jobs; the liteparse/markitdown recipe is a *fallback* text-extraction
  tier for the OCR lane (below our main bar, but a cheap degraded mode); quota +
  delegation patterns as in 3.6.
- **Not covered**: all five §5 lanes (grep-confirmed by the deep pass).

### 3.8 kyuz0/amd-strix-halo-gfx1151-toolboxes — the hub

- **Purpose**: landing site (strix-halo-toolboxes.com) indexing the whole kyuz0
  ecosystem; hosts the canonical host-config quickstart, no code of its own.
- **Rhythm**: frequent but almost entirely cosmetic; substance = the `#config` section
  and the README repo list.
- **Latest (f1edf61)**: same boot params as 3.4; tuned `accelerator-performance`
  profile; Ubuntu udev-rule variant for kfd/renderD perms. New sibling repos surfaced
  this cycle: **llama-toolboxes-cockpit** (TUI for toolbox/GGUF management),
  **strix-halo-ds4-toolbox** (DwarfStar), and **pi-bench** (SWE-bench Verified Mini
  local coding benchmark, results at pi-local-coding-bench.dev — directly relevant to
  the pi harness, worth a standalone read; not in this baseline).
- **Applies now**: a new bullet in its README `## Repositories` list = a new repo to
  deep-read — that's this repo's whole delta value.
- **Not covered**: everything; it's a front door.

### 3.9 kyuz0/amd-strix-halo-vllm-toolboxes — vLLM, if ever

- **Purpose**: from-source vLLM + TheRock ROCm image for gfx1151, including a 2-node
  RDMA/RoCE tensor-parallel cluster setup; ~11 numbered source patches to make
  CDNA-assuming vLLM/AITER run on RDNA.
- **Rhythm**: bursty (multi-commit days, then silent weeks); PR-driven with one
  external contributor.
- **Latest (6446b95, 2026-06-17)**: FP8 W8A8 via Triton kernels (opt-in, no native FP8
  hardware); TP=2 across two boxes measured e.g. Llama-3.1-8B 388→712–773 t/s
  aggregate; **GPU-util capped at 0.90** to prevent UMA OOM (over-committing GPU util
  starves system RAM — unlike a discrete GPU); Thunderbolt direct-connect documented as
  the cheap interconnect (MTU 9000) vs 100 GbE RDMA cards; amdsmi doesn't work in
  containers on this APU.
- **Applies now**: the 0.90 UMA ceiling is a scheduling constant for tally on
  co-tenanted boxes; the TB fallback matches our existing TB3 data plane; only relevant
  as a lane if we ever want one large model TP-split across both boxes instead of
  llama.cpp pipeline split (ds4 already owns that job class).
- **Not covered**: all five §5 lanes, llama.cpp/GGUF entirely, NixOS.

### 3.10 kyuz0/amd-strix-halo-comfyui-toolboxes — image/video gen

- **Purpose**: ROCm 7 + PyTorch + ComfyUI toolbox for diffusion image/video
  *generation* (successor to the discontinued image-video repo, 3.13).
- **Rhythm**: solo, one feature/fix per commit; benchmarks re-run whenever a model
  lands, dropped as dated `docs/benchmark_results*.json`.
- **Latest (c2ef528)**: `--disable-mmap` CRITICAL (same >64 GB ROCm mmap issue);
  validated model families with cold timings on gfx1151 — Qwen-Image-2512 4-step LoRA
  75 s, LTX-2 T2V ~615 s, HunyuanVideo 1.5 720p ~930–950 s, Wan 2.2 14B ~2000 s
  (~33 min/clip); "Strix Halo doesn't support FP8 anyway" — BF16 preferred, corroborating
  3.1; portable env knobs `TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1`,
  `TORCH_BLAS_PREFER_HIPBLASLT=1`.
- **Applies now**: if a generation lane ever opens, these are the three benchmarked
  fit-in-128GB video models with per-clip costs to budget into tally windows; the env
  knobs apply to any torch-ROCm workload (VibeVoice, heretic runs).
- **Not covered**: video *editing/captioning* (generation only), all other §5 lanes,
  LLM serving.

### 3.11 kyuz0/amd-strix-halo-llm-finetuning — the training sibling

- **Purpose**: toolbox for LoRA/QLoRA/full fine-tuning (Gemma-3 family, Qwen-3,
  GPT-OSS-20B) on gfx1151, incl. 2-node DDP/FSDP with a memory-estimating TUI launcher.
- **Rhythm**: continuous small commits with same-day revert cycles on brittle pins
  (unsloth, custom RCCL) — treat single commits to those as provisional.
- **Latest (093a23c)**: measured budget table (e.g. Gemma-3 12B: full FT 115 GB/25 min,
  QLoRA 26 GB/23 min; 27B full FT impossible even 2-node — LoRA/QLoRA required);
  bitsandbytes built from source for gfx1151 (relevant to the loadout's
  "bitsandbytes-on-gfx1151 broken" note — a working recipe now exists *inside this
  image*); flash-attention is inference-only on this stack, training needs eager
  attention; unsloth pinned to a fragile commit + hand-applied PR.
- **Applies now**: nothing until a fine-tuning lane is ever ruled in; the
  memory-estimation-before-dispatch logic in `start-finetuning-cluster.py` is the same
  shape as a tally capacity pre-flight; parks the question of self-abliterating heretic
  models (this image's bitsandbytes may unblock what the loadout marked broken).
- **Not covered**: all five §5 lanes, inference/serving entirely.

### 3.12 kyuz0/amd-strix-halo-benchmarking-scripts — diffusion-VAE micro-bench

- **Purpose**: misleading name — exclusively VAE encode/decode micro-benchmarks (WAN
  video VAE, Qwen-Image VAE) on ROCm nightly, hunting the fastest dtype/tiling combo.
- **Rhythm**: bursty single-person sessions, then quiet; quarterly check suffices.
- **Latest (bc276db)**: never run VAEs untiled (7–12x slower, "unusably slow");
  Qwen-Image VAE best = bf16 + native tiling (~12x speedup); WAN VAE best = fp32 +
  manual 128 px tiles; MIOpen env toggles that help elsewhere *hurt* here; scripts
  clear MIOpen cache + reload the model between configs to avoid measurement
  contamination.
- **Applies now**: only if the ComfyUI lane opens — then these are mandatory VAE
  settings; the cache-clearing methodology is reusable boilerplate for any gfx1151
  micro-bench we write as a tally witness/validation step.
- **Not covered**: everything else including classic LLM inference.

### 3.13 The dead/base layers — image-video-toolboxes + pytorch-aotriton

- **kyuz0/amd-strix-halo-image-video-toolboxes** (b833ec3): **DISCONTINUED** — terminal
  commit redirects to the comfyui repo (3.10). Kept in the baseline for reference; do
  not poll it again. Its lasting artifacts: the WAN2.2 reduced-res run recipe and the
  Ubuntu udev rule.
- **kyuz0/amd-strix-halo-pytorch-gfx1151-aotriton** (6965ae5): 2-commit base-image repo
  compiling PyTorch+AOTriton for gfx1151 (wraps lhl/strix-halo-testing build scripts);
  prerequisite for the vLLM image, zero benchmarks. Watch only the version pins. The
  `therock-env.sh` env-var wiring is the reference if we ever compile ROCm/Triton
  kernels outside a toolbox on NixOS.

### 3.14 kyuz0/strix-halo-ds4-toolbox — the ds4 lane's upstream

- **Purpose**: packages antirez's ds4 (DeepSeek V4 Flash engine, not llama.cpp) for
  gfx1151, incl. the multi-node pipeline-parallel image our dual-node runbook uses,
  plus a cockpit TUI. Loadout row 4's serving image.
- **Rhythm**: very high, CI-driven — upstream antirez/ds4 polled every 4 h,
  auto-rebuild on new SHA; frequent no-op CalVer bump commits are noise.
- **Latest (30e634b)**: imatrix quants strongly preferred for agentic/coding at Q2;
  KV-cache **disk offloading** (`--kv-disk-dir`, sha1-keyed checkpoint files) explicitly
  recommended for coding-agent workloads to skip re-prefill of repeated system prompts
  — survives restarts (our runbook's Appendix A gate on trustedInterfaces still applies
  before enabling it dual-node); `HF_XET_HIGH_PERFORMANCE=1` replaces
  `HF_HUB_ENABLE_HF_TRANSFER` in download scripts; firmware pin corroborates 3.4
  (avoid 20251125, use 20260110+); cockpit now uses `--keep-groups` under podman;
  abliterated DeepSeek GGUF variants (CyberNeurova) appeared in its catalog — a
  candidate feed for the decensored-pool lane.
- **Applies now**: the KV-disk flags for any long-lived server behind pi/tally; the
  4-hourly upstream-SHA-poll + conditional-rebuild-dispatch CI pattern is exactly the
  shape of a tally-enqueued rebuild trigger; PATH-shadowing gotcha inside toolboxes
  (host ~/.local/bin shadows container binaries).
- **Not covered**: all five §5 lanes; single-engine, single-model-family by design.

### 3.15 ciru-ai/benchmarks — the lab behind lab.ciru.ai

- **Purpose**: living benchmark dashboard (llm.ciru.ai, "Ciru Inference Lab") for one
  Strix Halo box — llama-bench throughput, custom AMD quant formats (ROCmFP4/ROCmFPX),
  speculative-decoding races (DFlash/PFlash/MTP), NPU telemetry, quality/tool-calling
  evals. Maintained *by an AI agent* per its own `agents.md` playbook. This resolves
  the watch list's lab.ciru.ai question as far as public code goes.
- **Rhythm**: ~2 commits/day since 2026-04; findings land as dated bullets atop
  `BENCHMARK_HISTORY.md` + standalone report pages + regenerated dashboard data.
- **Latest (bc3dc2a, 2026-07-10)**: ROCmFP4/FPX quants show +33–91% decode uplifts over
  stock quants on Qwen configs (needs a Chadrock-style fork, not stock llama.cpp);
  per-family KV guidance — Gemma 4 regresses badly on q8 KV (keep f16), Qwen3.6 is fine
  on q8_0; small-draft speculative decoding *inverts* at long active context (17.8 t/s
  → below the 6.1 t/s baseline at ~24k active tokens); batch sweep found `-b 2048 -ub
  1024` best at 128k prompt; NPU FastFlowLM ladder published (Qwen3.5 0.8B–9B, up to
  32k ctx); their strict-vs-comparable llama-bench row schema (model|backend|kv|batch|
  ubatch|split|build + memory peaks) is a reusable convention for any results store we
  build over tally jobs.
- **Applies now**: the per-family KV defaults and the long-context speculative-decoding
  inversion go straight into future server-unit flag choices; ROCmFPX quants are the
  community-quant lane the watch list flagged (jcbtc/chadrock scene) — watch, don't
  adopt until reproduced.
- **Not covered**: all five §5 lanes (grep-confirmed).

### 3.16 ciru-ai/strix-halo-evo-x2-evidence — NixOS peer evidence

- **Purpose**: one-time (so far) public evidence artifact — sanitized benchmark DBs +
  curated narrative from a GMKtec EVO-X2 running **NixOS** — the closest thing to a
  peer of our exact stack. Feeds strix-halo-guide (3.3) as its data lane.
- **Rhythm**: 2 commits total; any future commit is the signal.
- **Latest (0d51b66)**: headline result — **NPU as sidecar**: auxiliary work on the NPU
  added +3.29% latency to a 64k-context main iGPU workload vs +68.96% when the same aux
  work ran as a second iGPU model. Achieved with **IOMMU kept ON**
  (`iommu.passthrough=0`) specifically to keep the NPU usable — directly in tension
  with the kyuz0 `amd_iommu=off` GTT-maximizer recommendation and therefore evidence
  *for* the loadout §6 NPU/kernel-param rulings, not just a data point. Also: tuned
  27B/35B routes pairing >90 t/s with 0.90+ HumanEval+; served/API numbers matter more
  than bare llama-bench for MTP routes.
- **Applies now**: the NPU-sidecar-vs-second-iGPU-tenant measurement is the single most
  decision-relevant community number for tally's low-priority job placement; the NixOS
  26.05 + 2 GB VRAM carve + UMA baseline validates our box config.
- **Not covered**: all five §5 lanes; publishes outcomes only, zero run commands or nix
  expressions.

## 4. Delta-refresh protocol

Baseline: `~/Downloads/local-ai-june11-references/MANIFEST.json` (2026-07-11, all 17
clones `--filter=blob:none`, full history). Procedure per repo:

```
cd ~/Downloads/local-ai-june11-references/<repo>
git fetch
git log --oneline <pinned>..origin/HEAD -- <watched paths>   # read ONLY this delta
```

Intended cadence: a **weekly-or-monthly tally-scheduled sweep** (the §3 sweep of
`strix-halo-llm.md`) that reads only the delta and emits the digest artifact. Concept
only — no units defined here, nothing enqueued; units land declaratively in the flake
when wired, per the tally paradigm.

| Repo | Pinned SHA | Delta recipe (watched paths + notes) |
|---|---|---|
| sypherin/strix-halo-setup | `6aaaa4a7` | `README.md docs/ systemd/ bin/strix-llm-switch.sh configs/claude-code-router.config.json` — README is rewritten wholesale, diff whole file; new features arrive as new `docs/<topic>.md`; watch `systemd/*.service` for flag flips |
| boxwrench/tesla_agent | `6b788127` | `README.md CHANGELOG.md reference/reproducibility-matrix.md guide/07* guide/08* docs/app.js` — a diff touching the matrix or CHANGELOG "Unreleased" = ladder pivot worth re-reading |
| hogeheer499/strix-halo-guide | `19cc7d77` | `CURRENT_MODELS.md README.md data/headline_claims.csv data/raw/` — new `data/raw/<date>/` dir = new evidence run; weekly is enough |
| kyuz0/amd-strix-halo-toolboxes | `310c852e` | `README.md docs/ toolboxes/` — README Stable-Config table (kernel/firmware pins) and `docs/troubleshooting-firmware.md` get regressions first; CI rebuilds are the publish trigger, not human cadence |
| kyuz0/amd-strix-halo-voice-toolbox | `ab133127` | whole history (14 commits, small) — diff `Dockerfile README.md scripts/vibevoice`; check Docker Hub tags too (manual workflow_dispatch, CI may not have run) |
| kyuz0/local-agent-builder | `e5b04892` | `skills/local-agent-builder/SKILL.md .../resources/docs/ .../examples/basic-tui-agent/src/config_template.yaml EXAMPLE_PROMPTS.txt` — new docs file = new pattern; never publishes perf numbers |
| kyuz0/deep-research-agent | `75671f51` | full re-read if commit count grows past 3; then `README.md src/prompts.py src/config_template.yaml eval/` |
| kyuz0/amd-strix-halo-gfx1151-toolboxes | `f1edf618` | `README.md docs/index.html` — only the `<section id="config">` block and the `## Repositories` list matter; a new repo bullet = new deep-read target |
| kyuz0/amd-strix-halo-vllm-toolboxes | `6446b959` | `README.md docs/results.json scripts/models.py scripts/patch_strix.py Dockerfile` — bursty; pins (ROCm/torch/vLLM) live in Dockerfile ARGs |
| kyuz0/amd-strix-halo-comfyui-toolboxes | `c2ef528b` | `README.md Dockerfile scripts/ docs/benchmark_results.json refresh-toolbox.sh` — new dated `benchmark_results_*.json` = fresh numbers to extract |
| kyuz0/amd-strix-halo-llm-finetuning | `093a23c0` | `README.md workspace/ Dockerfile custom_libs/` — treat single commits touching unsloth pin / librccl as provisional until they survive a follow-up commit |
| kyuz0/amd-strix-halo-benchmarking-scripts | `bc276dbc` | `README.md qwen_diffusion_bench.py results_*.txt` — quarterly unless velocity resumes |
| kyuz0/amd-strix-halo-pytorch-gfx1151-aotriton | `6965ae5b` | both Dockerfiles + `scripts/therock-env.sh` — watch the AOTriton commit pin and TheRock index URL only |
| kyuz0/amd-strix-halo-image-video-toolboxes | `b833ec30` | **DEAD — do not poll.** Superseded by comfyui-toolboxes; redirect any residual watch there |
| kyuz0/strix-halo-ds4-toolbox | `30e634b4` | `README.md AGENTS.md toolboxes/ ds4-strix-halo-cockpit/src/assets/*.json docs/results.json` — filter out `chore(cockpit): bump version` noise; follow up only when bundled with a substantive file change |
| ciru-ai/benchmarks | `bc3dc2a8` | `BENCHMARK_HISTORY.md` (dated bullets at top of "Agent quick recall") + `agents.md` + new dirs under `research/ reports/ tooleval/ dflash/`; ~2 commits/day, weekly sweep catches the window |
| ciru-ai/strix-halo-evo-x2-evidence | `0d51b66e` | any commit is the signal; then `README.md manifest.md MODEL_LINKS.md data/` — row-count drift in the sqlite/csv exports = new benchmark run |

Full 40-char SHAs are in `MANIFEST.json`; the table's 8-char prefixes are unambiguous
within each repo. When a sweep advances a pin, update the manifest *and* this table in
the same commit.

## 5. The uncovered lanes — confirmed by the deep pass

Every brief's `not_covered` list was consolidated; the doctrine doc's §4 claim holds
with zero exceptions: **no watch-list repo covers any of our specialized lanes.** One
line each on why, and where our canonical material lives:

- **Academic-paper OCR** — the community's ceiling is a 650M Surya OCR service (3.1)
  and generic liteparse/markitdown PDF-to-text (3.7); nothing layout-, citation-, or
  multi-column-aware. Ours: `github.com/mecattaf/academic-rag` + loadout rows 9–10 +
  `strix-halo-llm.md` §4.1.
- **Call diarization/transcription** — zero content anywhere; Whisper is only ever
  namechecked as a hypothetical NPU workload. Ours: the transcription/diarization
  comparison note (§2) + loadout row 2 + `strix-halo-llm.md` §4.2.
- **Streaming STT** — nothing resembling asr-rs exists in the corpus; the community is
  GPU-serving-centric and this lane is CPU-only by design. Ours:
  `github.com/mecattaf/asr-rs` branch `v2-parakeet` + loadout row 1 +
  `strix-halo-llm.md` §4.3.
- **Video editing/captioning** — the corpus covers video *generation* (3.10) only;
  no NLE-adjacent, subtitle, or existing-footage workflow anywhere. Ours: no canonical
  note yet — open lane; the generation-model cost table (3.10) is the only adjacent
  community input.
- **Deterministic heavy builds** — the community's only "builds" are opportunistic
  inference-stack compiles (nightly-floating pins, no reproducibility guarantees); the
  patched-Chromium rebuild remains the exemplar tally job with no community analog.
  Ours: tally repo `docs/` for the job class; the parked Chromium `out/` tarballs
  question is loadout §6's deletion ruling.

The corollary from the doctrine doc stands: the watch list keeps us current on the
shared substrate; these five lanes are the differentiators, and their canonical
material is ours to maintain.
