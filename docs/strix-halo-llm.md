# strix-halo living device — community watch + specialized LLM lanes

Doctrine captured 2026-07-11. Durable reference, not a task list: the board owns urgency,
this doc owns the map. Companion to `migration-journal/ds4-dual-node-lessons.md` (the
dual-node runbook) and the loadout plan in the notes repo (see Pointers).

## 1. The device is alive

Both fleet boxes are the same hardware: **AMD Ryzen AI MAX+ 395 (Strix Halo), Radeon
8060S gfx1151, 128 GB unified RAM**, GTT-pinnable to ~124–128 GB. That exact SKU has an
active community that publishes *periodic* findings — which models newly fit, which
quants newly work, which ROCm/kernel combos newly break. The experience of owning the
device therefore changes week to week without us touching it: a model that OOM'd last
month runs today because someone shipped a better imatrix quant or a toolbox image bump.

Two consequences, and this doc holds both:

1. **Watch the community** — a fixed source list swept on a schedule (§2–3), so the
   fleet inherits upstream findings instead of rediscovering them.
2. **Own the lanes the community doesn't cover** (§4) — the specialized workflows
   (academic OCR, call transcription, streaming STT, heterodox generation, TTS) that the
   general "run big models on Strix Halo" repos barely touch. The watch list keeps us
   current; the lanes are the differentiators.

## 2. Community watch list

Fixed sweep targets. Each is checked for new commits/releases/results, not read cover to
cover every time.

| Source | What it publishes |
|---|---|
| `github.com/kyuz0/*` — `amd-strix-halo-toolboxes`, `strix-halo-ds4-toolbox`, `amd-strix-halo-voice-toolbox` | The state-of-the-art container images + run recipes for this exact GPU (llama.cpp, ds4 multi-node, PyTorch-ROCm voice stack); our whole serving protocol is ported from these (loadout plan §3) |
| `github.com/sypherin/strix-halo-setup` | End-to-end Strix Halo setup guide — kernel params, memory tuning, serving stacks |
| `github.com/boxwrench/tesla_agent` (README) | A worked local-agent build on comparable hardware — model picks + harness patterns worth diffing against ours |
| `github.com/hogeheer499-commits/strix-halo-guide` → `COMMUNITY_RESULTS.md` | Crowd-sourced benchmark results per model/quant on Strix Halo — the fastest way to learn what newly fits and at what tok/s |
| `lab.ciru.ai` | Strix Halo lab findings. **GitHub repo still unlocated** — the site is the sweep target until the repo is found; locating it is a standing sweep sub-goal |
| `huggingface.co/jcbtc/qwable-5-27b-chadrock-v2-rocmfp4` | Example of the community-quant lane: rocm-fp4 builds cut for this hardware; watch the author + surrounding quant scene for new drops |
| `github.com/kyuz0/local-agent-builder` + `github.com/kyuz0/deep-research-agent` | Deterministic harness engineering for local agents (general → specialized skill distillation). We mine the *patterns*; Tom's ruling is to run the **pi agent harness directly**, not adopt these harnesses |

## 3. Weekly check-in: local agents sweep the list

The sweep is itself a local-AI job, scheduled on **tally** (v0.1.0 alpha, live on the
coordinator). Conceptually:

- A **systemd timer** fires the weekly cadence; its only action is
  `tally enqueue --kind pi` (or `--kind shell` for the dumb fetch steps) — admission
  through Seam A like every other job, never a daemon squatting on the box.
- The enqueued agent walks §2: diff each repo since last sweep, pull new
  `COMMUNITY_RESULTS.md` rows, scan for new quants/images/kernel findings relevant to
  gfx1151, and check whether lab.ciru.ai's repo has surfaced.
- Output is a digest artifact (what's new, what it changes for the loadout, what to
  try), landing wherever tally routes evidence — it feeds the notes inbox, not the
  board directly.
- It doubles as the **model ledger**: a queue of models to evaluate plus the record of
  what we already tried, so re-evaluations aren't accidental.

Interactive-path law still applies: the sweep is batch, presence-gated, and never
touches launch paths. Unit definitions are deliberately *not* in this doc — they land
declaratively in the flake when wired, lease-activated per the tally paradigm.

## 4. The specialized lanes (what the community doesn't cover)

The §2 repos answer "how do I run big models on this GPU." They have little to say
about the workflows below — which is exactly why they're ours. Row numbers refer to the
loadout plan's model inventory (§1 of that note).

### 4.1 Academic-paper OCR drain

- **What**: nightly batch OCR/RAG over the ~4.7k academic-paper sidecars in the notes
  knowledge shelf — the deliberate daily drain. The flagship tally consumer: it holds
  the worker GPU lease for its window.
- **Models**: Qwen3-VL-8B Q8_0 (fast pass) + Qwen3-VL-32B Q4_K_M (refine) +
  Qwen3-Embedding-8B, ~35 GB all-resident, servers launched sequentially. A ~63 GB
  judge model exists as an unwired exclusive-window stage.
- **Loadout rows**: **9** (suite) and **10** (judge). Pipeline code: academic-rag repo.

### 4.2 Call-recording transcription + diarization

- **What**: batch "local Granola" — a recorded 60-min call goes in, a diarized
  who-said-what transcript comes out. Never resident; a tally batch job on the worker.
- **Candidates** (from the diarization survey note): **VibeVoice-ASR-7B** (end-to-end
  multimodal LLM, 64K ctx, processes 60 min in one pass — current loadout pick);
  **MOSS-Transcribe-Diarize 0.9B/Pro** (one-pass joint text+timestamps+speaker tags,
  GGUF available); **WhisperX** (modular pipeline, word-level sub-100ms alignment —
  the pick if click-word-to-seek UX ever matters); **FunASR** (Alibaba industrial
  toolkit, robust long-form). Decision curve: end-to-end models for clean prose,
  WhisperX for timestamp precision.
- **Loadout row**: **2** (VibeVoice-ASR-7B on the worker, kyuz0 voice-toolbox image).

### 4.3 Live streaming STT (asr-rs)

- **What**: instant dictation on the coordinator — live grey preview plus offline
  finalize. Tom's active workstream; described here, not prescribed.
- **Models**: dual-Parakeet (EOU-120M + TDT-0.6b-v2), fp32 ONNX, 0.9% WER at 38.75x RT.
- **CPU-only by design** — the iGPU is 3.6x *slower* for streaming ASR, so this lane
  never takes a GPU lease and is always-on. It is also the lane most invisible to the
  community repos, which are GPU-serving-centric.
- **Loadout row**: **1** (coordinator, native nix-packaged Rust binary, branch
  `v2-parakeet` of the asr-rs repo).

### 4.4 Decensored hypothesis-generator pool

- **What**: ≥3 decensored/abliterated models (including "the heretic one" —
  `p-e-w/heretic`-style variants) as a *heterodox hypothesis generator*: high recall,
  terrible precision, **never a decision-maker**, excluded from automatic routing by
  policy. Manual lease only, worker sandbox lane.
- **Models**: prebuilt `*-heretic` HF GGUFs preferred over self-abliterating
  (bitsandbytes on gfx1151 is broken); exact ≥3 picks are an open ruling.
- **Loadout row**: **8**.

### 4.5 Voice TTS

- **What**: zero-shot voice-clone TTS from a 10–60 s reference sample; batch on the
  worker, optional streaming lane if a ruling ever wants interactive TTS.
- **Models**: **VibeVoice-TTS-1.5B** (+ optional Realtime-0.5B). **Retracted-weights
  caveat**: Microsoft pulled the weights 2025-09-05; only community HF mirrors exist,
  and fetching from one is itself an open ruling. Engine alternatives
  (Qwen3-TTS/CustomVoice, Kyutai Pocket) remain on the table.
- **Loadout row**: **3** (kyuz0 voice-toolbox image, which carries the known
  llvmlite/ROCm and bf16-resampler shims).

## 5. Pointers

- **Loadout plan** (10-row inventory, TB3 topology, NixOS-vs-kyuz0 protocol table,
  phases P0–P7, open rulings): `mecattaf/notes` →
  `inbox/local-llm-loadout-plan.md` — the operational detail this doc deliberately
  does not duplicate.
- **tally** (queue/lease/witness substrate; Seam A = `tally enqueue`):
  `github.com/mecattaf/tally` — spec + CLI surface under its `docs/`.
- **academic-rag** (the §4.1 OCR/RAG pipeline): `github.com/mecattaf/academic-rag`.
- **asr-rs** (the §4.3 streaming STT engine, branch `v2-parakeet`):
  `github.com/mecattaf/asr-rs`.
- **ds4 dual-node runbook** (both-GPUs-exclusive job class):
  `migration-journal/ds4-dual-node-lessons.md` in this directory.
- **Community digest** (deep-pass baseline of the §2 watch list, pinned SHAs +
  delta-refresh recipes, 2026-07-11): `strix-halo-community-digest.md` in this directory.
