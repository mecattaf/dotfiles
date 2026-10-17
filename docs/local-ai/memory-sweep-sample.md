# memory-sweep-sample: the bounded Hy-Memory + TencentDB-Agent-Memory trial

A one-shot, hand-run way to see whether Tencent's Hy-Memory-30B-A3B (a
memory-writer model) behind TencentDB-Agent-Memory's MemoryCore extracts
useful memories from a small sample of Tom's notes and chat logs, for desk
thread T-15 (the one-time triage). Decided in `DECISIONS.md` 2026-10-17; the
four research reports are under `~/today/2026-10-17-tencent-memory/`.

Nothing here is scheduled and nothing is resident. The flake check
`memory-sweep` fails if any host gains a unit or timer named `memory-sweep*`
or `hy-memory*`.

## What is installed (strix only)

| Command | What it is |
|---|---|
| `memory-sweep-sample plan \| run \| report <run-id> \| clean <run-id>` | the experiment; writes only under `~/.local/state/memory-sweep/<run-id>/` |
| `hy-memory-serve` | the hand-run `llama-server` for the `hy-memory-30b-a3b-q8-0` row, loopback `:8081`, one slot, 32k context, reasoning off |

Both come from `pkgs/memory-sweep`. `hy-memory-serve` wraps nixpkgs'
`llama-cpp` build 10063 (Vulkan) by store path, not the fleet's `llama-server`
on PATH: the gfx1151 build from nix-strix-halo is 9925 (2026-07-08), 68 commits
before llama.cpp merged the `hy_v3` architecture (2026-07-13), and both
nix-strix-halo packages evaluate to 9925 at the current lock regardless of the
`llama-cpp-master` input. `nix eval --raw .#memory-sweep.passthru.llamaServer`
prints the wrapped binary.

## Prerequisites (operator, in order; no switch performs any of them)

1. Switch the NAS, then `sudo systemctl start library-fetch` (about 32 GB from
   Hugging Face: the Q8_0 GGUF, `chat_template.jinja`, `SHA256SUMS`,
   `conversion.json`, verified against the pinned oids).
2. Switch the strix. `/etc/local-models/wanted.json` now lists the row.
3. `sudo local-models-borrow --dry-run`, then `sudo local-models-borrow --yes`.
   The borrow keeps an 8 GiB reserve; on 2026-10-17 the root had 52 GB free,
   so the loan leaves about 22 GB. If that is too tight, the Q6_K row (23.0
   GiB; bytes, oid and hash in `04-design.md` section 3.1) is a one-row swap.
4. Optional: `podman pull docker.io/agentmemory/memory-core@sha256:b37fa9f2e1e4993ab69e2b4522ec5897f075a7031e01e31fed080acdcaf96c98`
   (248 MB). Otherwise `run` pulls it, and says so before it does.

## The six commands

```console
memory-sweep-sample plan                       # 5 + 5 sample, no model, no container
memory-sweep-sample run --dry-run              # plan.json and payloads/ only
memory-sweep-sample run                        # starts hy-memory-serve, then MemoryCore, seeds, tears down
cat ~/.local/state/memory-sweep/<run-id>/report.md
memory-sweep-sample report <run-id>            # re-render
memory-sweep-sample clean <run-id>             # delete that run directory, nothing else
```

Useful flags on `run`: `--notes-n`, `--chats-n`, `--seed` (default 20261017),
`--notes-scope own` (journal, continuity, personal minus estate),
`--prompt-mode code` (MemoryCore's engineering prompt; may return zero atoms
on non-engineering text), `--transport live` (the asynchronous
`/v3/conversation/add` path instead of the blocking `/seed`), `--no-serve
--llm-url http://127.0.0.1:8081/v1` to use a server you started yourself,
`--max-turns` (60), `--budget-seconds` (3600).

## What the run directory holds

| Path | Content |
|---|---|
| `plan.json` | seed, roots, eligible counts, skipped counts, each sampled file with bytes, mtime, sha256 |
| `payloads/NN-note-*.json`, `payloads/NN-chat-*.json` | the seed sessions exactly as sent |
| `llama-server.log`, `probe.json` | the writer's log and the quickstart probe (expects a JSON object with a `memories` list) |
| `tdai-gateway.yaml`, `core.cmd`, `core.log` | the rendered MemoryCore config, the podman command, its log |
| `core-data/` | MemoryCore's own state: `seed-*/records/*.jsonl` (L1 atoms), `scene_blocks/*.md` (L2), `manifest.json`; this is the L0 copy of the sampled text and it is Tom's to delete with `clean` |
| `results.json` | every HTTP response, the `/metrics` deltas, the versions |
| `report.md` | the readable result |

## How to read report.md

The question is "if and how this works". The report gives: the sample table;
per source the rounds and messages sent, HTTP status and seconds; atoms by type
(`persona`, `episodic`, `instruction` in `chat` mode) with their content and
priority; atoms per 1,000 input characters; prompt and generated tokens per
1,000 input characters; what was skipped and why; the exact llama-server path
and image digest. Every number is MEASURED from the run directory; the atom
field names are read generically from MemoryCore's records and that shape is
INFERRED from the checkout at `e9a82935`.

## What the command never does

- Never writes into `~/notes`, `~/archives`, `/mnt/nas`, `~/rawa` or the
  dotfiles checkout: it refuses a run directory under any of them (exit 2,
  naming the path) and opens inputs read-only.
- Never reads the live `~/.claude*/projects` or `~/.codex/sessions`; the
  archive mirrors are the corpus. Never `subagents/`, never
  `references/learnings`, `references/deferred`, `references/personal/estate`,
  `crm`, any `.env`, notes over 512 KB or under 200 bytes, chats over 20 MB.
- Never downloads weights: `hy-memory-serve` refuses `-hf`, `--hf-repo` and
  `--hf-file`; bytes come through `library-fetch` and `local-models-borrow`.
- Never stops Halogen, Gufo, Herdr or the user manager: if the memory
  preflight refuses (MemAvailable below model size plus 12 GiB), run it when
  the box is quieter or swap the row to Q6_K.
- Never leaves anything running: `podman stop memory-sweep-core` and the
  llama-server child are torn down on exit and on signals.

## Teardown and exit

`memory-sweep-sample clean <run-id>` deletes the run directory. The GGUF and
the image stay on disk; the retire runbook in `docs/nas/model-archive.md` and
`sudo local-models-prune` are the exit for the row if Tom drops it;
`podman rmi` for the image.

## Fallbacks

- If llama-cpp 10063 (Vulkan, RADV) fails to load the GGUF on a metadata or
  template error: the documented fallback is the upstream image
  `ghcr.io/ggml-org/llama.cpp:server-vulkan` pinned at the digest captured
  2026-10-17, `sha256:550a05f5f8d408fe6b6aef302f4237d40bdcf83b615cd9deced7f0e72369dda2`,
  run by hand with `--device /dev/dri` and the same flags, then `run --no-serve`.
- If `POST /seed` answers 404 on the published image, `run` falls back to
  `--transport live` and the report says so.
- If the container cannot reach `127.0.0.1:8081` under rootless
  `--network=host`, pass `--llm-url http://host.containers.internal:8081/v1`
  and add `--add-host=host.containers.internal:host-gateway` to `core.cmd`.
- Bumping `nix-strix-halo` (its llama.cpp at `7ac59a6e`, 2026-09-27, also has
  `hy_v3`) would serve the model on ROCm, at the cost of rebuilding the whole
  gfx1151 ROCm plane (the 8.3 GiB uncached therock NAR named in
  `modules/strix-ai.nix`). Not in this change; Tom's option.

## Tests

```console
nix flake check --offline --no-build                  # eval-time asserts
nix build .#checks.x86_64-linux.memory-sweep          # unit tests in the sandbox
runtime-test -- env MEMORY_SWEEP_AI_MEMORY=$PWD/home/dot_claude/skills/drain/scripts/ai_memory.py \
  python3 -m unittest discover -s tests/memory-sweep -p 'test_*.py' -v
```

The live experiment itself is not run under `runtime-test` (rootless podman
needs the real runtime directory); it cleans no runtime directory and sources
no fragment.
