# Tencent memory stack for the T-15 sweep: findings record (2026-10-17)

What was learned before `pkgs/memory-sweep` and the `hy-memory-30b-a3b-q8-0`
row were added (DECISIONS.md 2026-10-17). Labels: MEASURED (a command run on
2026-10-17 and named in the source report), REPORTED (a vendor card, paper,
README or repo file says so), INFERRED (a reading of the above). No new claim
here goes beyond the four reports named in section 7. No em-dashes.

## 1. What Hy-Memory-30B-A3B is, and is not

| Claim | Label |
|---|---|
| `tencent/Hy-Memory-30B-A3B`, revision `64a460a9`, Apache-2.0, published 2026-10-15; `hy_v3` MoE, 48 layers, 128 experts with 8 active plus one shared, about 30B total and 3B active, 262k positions, BF16 60.1 GB | MEASURED (HF API, config.json) |
| It is a write-path "memory writer": the LLM a memory framework calls to decide what to store and how new evidence should ADD / UPDATE / DELETE entries. It is not a chat model and not a memory system. Retrieval and answering are the framework's job | REPORTED (model card, arXiv 2610.22196) |
| Trained to speak three frameworks' write protocols (Mem0, MemOS, Hy-Memory's Chat / Working / Coding) and claimed to transfer to a fourth (EverMemOS); two stages, on-policy distillation then chunk-level GRPO with attributed rewards | REPORTED (paper) |
| Vendor table: 55.49 macro average against Claude Opus 5's 54.62 and its own base's 47.66; the authors state that 0.01 to 0.02 margins are not significant and that seeds were not repeated | REPORTED; INFERRED: the honest reading is "a 3B-active writer matches frontier writers on this protocol and beats its base by 8 points"; the Opus comparison on Mem0 and MemOS is noise |
| Intended inference: `temperature 0`, `max_tokens 512`, `reasoning_effort: no_think`; the chat template defaults to `no_think` for unknown values | MEASURED (chat_template.jinja) |
| No independent benchmark exists | MEASURED (search, none found) |

## 2. What TencentDB-Agent-Memory is

| Claim | Label |
|---|---|
| Node/TypeScript, MIT, four services: MemoryCore (:8420, L0 to L3 pipeline), MemoryProxy (:8096), MemoryKnowledge (:8424), MemoryPanel (:8125); SQLite default with `sqlite-vec` and FTS5; MongoDB and Tencent VectorDB alternatives; no PostgreSQL | MEASURED (checkout `e9a82935`) |
| L0 raw messages, L1 atoms (`persona`, `episodic`, `instruction` in `chat` mode; project facts, decisions, SOPs in `code` mode), L2 markdown scenes, L3 persona; BM25 plus optional vectors fused by RRF | MEASURED (`v3-api-memorycore-doc.md`, prompt files) |
| Any OpenAI-compatible `/v1/chat/completions` works as the extraction LLM (`createOpenAI({ compatibility: "compatible" })`); the config gate needs a truthy `apiKey`, so `sk-local` is a literal, not a secret | MEASURED (`gateway/config.ts`) |
| `POST /seed` (standalone gateway) runs L0 to L3 on a batch synchronously and returns counts and an output directory; `/v3/conversation/add` plus `/session/end` plus `/v2/pipeline/status` is the asynchronous path | MEASURED (`gateway/{server,types,v2-router}.ts`) |
| The import tool `agents/asset-import.ts` already parses Claude Code, Codex and Pi jsonl, folds tool calls, drops harness noise, cuts messages at 8,192 chars and batches 100 | MEASURED |
| No mention of Hy-Memory, Hunyuan or any dedicated memory model anywhere in the tree; the two projects share a parent company and nothing else | MEASURED (`git grep`) |
| 29k stars, 2.0.3-beta.1 on 2026-10-13, squashed public history, tests not published, open data-loss issues (L0 write amplification #1621, cursor advance on L1 failure #1618, dedup failure #1640) | MEASURED (GitHub API, issue list); INFERRED: a fast-moving beta |
| Published image `agentmemory/memory-core@sha256:b37fa9f2e1e4993ab69e2b4522ec5897f075a7031e01e31fed080acdcaf96c98`, tag `1.0.3-beta.1` = `latest`, pushed 2026-10-13, 248 MB; no `v2.0.x` image tag | MEASURED (registry) |

## 3. The serving finding (the correction to report 01)

| Claim | Label |
|---|---|
| Installed `llama-server --version` on the strix: `9925 (ed8c261)` from nix-strix-halo's `llama-cpp-rocm-gfx1151`; its `libllama.so` has `hunyuan-moe` and `hunyuan-dense` and zero `hy_v3` strings | MEASURED |
| `ed8c261` is 2026-07-08; the `hy_v3` merge `2969d6d1` (PR #25395) is 2026-07-13; `compare` says behind by 68 | MEASURED (`gh api`) |
| Both `nix-strix-halo` llama packages evaluate to `9925` at our lock; the `llama-cpp-master` input (571d0d54, after the merge) is not what they build from, so report 01's "75 commits ahead" compared the wrong thing | MEASURED (`nix eval`) |
| nixpkgs at our pin ships `llama-cpp` 10063 (`7d56da7e`, 2026-07-17, 70 commits after the merge); `pkgs.llama-cpp.override { vulkanSupport = true; }` is `/nix/store/sxmas9mp...-llama-cpp-10063` and is on cache.nixos.org | MEASURED (`nix eval`, `nix path-info --store https://cache.nixos.org`) |
| Whether 10063 (Vulkan, RADV on gfx1151) loads the rapatsky GGUF converted against `f3363593` (2026-10-16) is untested; fallback is `ghcr.io/ggml-org/llama.cpp:server-vulkan@sha256:550a05f5...` | INFERRED; acceptance A6 of `04-design.md` decides |
| Gufo v0.16.0 (2026-10-16) lists no Hunyuan architecture | MEASURED (README) |

## 4. The fleet seams it plugs into

- Catalogue row in `lib/memory-writer-models.json`, merged by `lib/local-models.nix`, wanted by `modules/strix.nix`, pinned by the two exact lists in `flake.nix`. Bytes move only by `library-fetch` on the NAS and `sudo local-models-borrow --yes` on the strix (AGENTS.md model-byte doctrine). MEASURED today: strix root 52 GB free, so the 29.79 GiB loan leaves about 22 GB over the 8 GiB reserve.
- `hy-memory-serve` is the "operator serves the small GGUFs by hand" shape DECISIONS.md kept on 2026-09-11; it is not a server module because nothing is resident.
- MemoryCore runs as a hand-run rootless podman container by digest with `--network=host`, SQLite, embeddings off (the "no embeddings server" line in AGENTS.md stands).
- The chat normaliser is `home/dot_claude/skills/drain/scripts/ai_memory.py` (`load_jsonl_stably`, `normalize_trace`), already covered by `tests/ai-memory`; `memory_sweep.py` imports it by store path and adds no parser.
- Nothing scheduled: the `memory-sweep` flake check asserts no host has a unit or timer named `memory-sweep*` or `hy-memory*` (AGENTS.md "Scheduled work", Tom 2026-09-30).

## 5. What the experiment measures and how to read report.md

`memory-sweep-sample run` samples 5 notes and 5 chats deterministically (seed 20261017) from the eligible population (journal, continuity, knowledge, devlogs, archive, personal minus estate; the two archive mirrors minus subagents), builds seed sessions (notes as 8,000-char user rounds headed by `Note <path>, modified <date>`; chats as normalised user/assistant rounds capped at 8,192 chars and 60 turns), probes the writer with the model card's quickstart prompt, seeds MemoryCore once per session over `POST /seed`, and renders `report.md`: atoms by type and per 1,000 input chars, seconds and tokens per source, every atom's content, what was skipped. Every number is MEASURED from the run directory; the atom field names are read generically (INFERRED shape). The report is meant to answer "if and how this works" in one read; the next sample size is arithmetic from the per-source seconds.

## 6. The three pairings, ranked

1. Hy-Memory framework (`hy-memory` 2.0.x on PyPI) + Hy-Memory-30B-A3B: the trained-for pairing; needs an embedder the fleet does not run. REPORTED (framework README).
2. Mem0 + Hy-Memory-30B-A3B: trained-for, mature, no Tencent dependency. REPORTED (paper).
3. TencentDB-Agent-Memory + Hy-Memory-30B-A3B: not trained for, not documented by either vendor; mechanically simple (one OpenAI-compatible URL). INFERRED: a hypothesis to test.

Only the third is wired here, because it is the pairing Tom named ("nice complement"), and because MemoryCore's `/seed` route makes a bounded, teardown-safe one-shot possible without an embedder. If the trial shows weak atoms, the next experiment is pairing 2 on the same sample and seed, not a bigger run of pairing 3.

## 7. Sources

Reports under `/home/tom/today/2026-10-17-tencent-memory/`:
`01-hy-memory.md` (the model), `02-tencentdb-agent-memory.md` (the stack,
checkout `/home/tom/Downloads/TencentDB-Agent-Memory` at `e9a82935`),
`03-current-stack.md` (what the fleet runs today), `04-design.md` (this
change's design, facts F1 to F22, decisions D1 to D10, acceptance A1 to A10),
`05-implementation.md` (the PR, the checks that ran).

## Unknowns and proposed defaults

1. Whether llama-cpp 10063 Vulkan loads the GGUF and at what tokens per second. Default: acceptance A6; fallback image above; record the outcome here.
2. Q8_0 on a 95 percent root versus the card's "practical default" Q5_K_M or Q6_K. Default: Q8_0 per the roster rule; Q6_K is a one-row swap.
3. Whether the published image's `POST /seed` matches the checkout. Default: `run` falls back to `--transport live` on 404 and the report says so.
4. Whether MemoryCore's L2/L3 tool-calling gets usable calls from a JSON-protocol writer. Default: L1 atoms are the result; L2/L3 listed only if present.
5. `chat` versus `code` prompt mode on Tom's corpus. Default: `chat`; `--prompt-mode code` on the same seed for comparison.
6. Whether `research_notes/` stays tracked. Default: this directory is its first tracked entry; if Tom says no, the same text moves to `docs/local-ai/research/`.
7. Whether pi sessions join the sample. Default: skipped and counted; a pi branch in `ai_memory.py` is a separate tested change.
8. Whether the row stays wanted after the trial. Default: it stays until Tom rules; `docs/nas/model-archive.md` and `local-models-prune` are the exit.
