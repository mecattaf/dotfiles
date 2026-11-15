# Local AI

The fleet runs one inference engine, Gufo, on strix-coordinator and a Library
of loanable model artifacts on the NAS. strix-worker is dormant until its
replacement arrives: it is not a builder and serves no model. Every claim on this page names the Nix
file that decides it.

| Engine | Where | Port | Serves | Started by |
|---|---|---|---|---|
| Gufo ([`../../modules/gufo.nix`](../../modules/gufo.nix)) | `gufo-llm.service` on strix-coordinator, the fleet endpoint | 8731 | `qwen3.8-flash-next` (resident), `qwen3.8-27b` (alternate) | boot; `gufo-switch` for the alternate |
| Gufo v0.33.0 + Qwen3-Embedding extension ([`../../modules/gufo-embedding.nix`](../../modules/gufo-embedding.nix)) | a llama-swap child on strix-coordinator | 8731 (llama-swap) | `qwen3-embedding-8b` (`POST /v1/embeddings`) | the first request naming it; unloaded after 600 s idle or by the next route |

The agent harness that uses them is dsh on the NAS (see [dsh](#dsh-on-the-nas)).
Halogen, the earlier engine, was retired on 2026-10-23, pi, the earlier
harness, on 2026-10-25, and local DeepSeek (ds4) on 2026-11-08; they appear
below only as history.

## The resident server: Gufo Flash-Next on strix-coordinator

[`../../modules/gufo.nix`](../../modules/gufo.nix) runs the native `gufo`
binary for gfx1151 (flake input `gufo`, no container), one systemd unit per
model. Both Strix configurations declare it from one block in
[`../../modules/strix.nix`](../../modules/strix.nix). `gufo-llm.service` loads
Qwen3.8 Flash-Next UD-Q4_K_XL (catalogue row `qwen38-flash-next-gguf`) with
its MTP predictor and BF16 vision projector from
`/var/lib/local-models/qwen38-flash-next-gguf`, loaned there from the NAS
Library. Its pre-start check refuses to start, and names the borrow command,
if any file is missing or the wrong size.

| | |
|---|---|
| Base URL | `http://strix-coordinator:8731` ([`../../lib/local-model.nix`](../../lib/local-model.nix); wired LAN `10.42.0.2`) |
| Model id | `qwen3.8-flash-next`: Gufo answers 404 to any other id and 400 to none |
| Shape | one session, 102400 tokens of context, thinking off, a 1 GiB prefix cache, `max_tokens` capped at 16384 |
| Endpoints | OpenAI-compatible `POST /v1/chat/completions` and `GET /v1/models` |
| Auth | none |
| Not available | `/v1/embeddings` on this text server (501; embeddings are the separate `qwen3-embedding-8b` route below), reranking, diarization |

```console
curl -s http://strix-coordinator:8731/v1/models
curl -s http://strix-coordinator:8731/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"ping"}],"max_tokens":16}'
```

strix-worker's configuration carries the same unit, but the host is dormant
and serves nothing. The two-host `gufo-tp2` rank and its RDMA link were
retired with the second Strix (#698).

## The alternate and the switch

The alternate is Qwen3.8-27B (`qwen38-27b-gguf` with the DFlash2 draft, four
sessions, 131072 tokens; or `qwen38-27b-q8-gguf` from the scoped
`/etc/gufo/27b-q8-wanted.json`), served as `qwen3.8-27b` on the same port.
Text units carry mutual `Conflicts=`, so one model owns the GPU at a time:

```console
sudo gufo-switch qwen38-27b   # stop Flash-Next, cold-load the 27B
sudo gufo-switch flash        # and back
sudo gufo-switch off          # stop every Gufo text unit, releasing the GPU
```

Gufo's DeepSeek V4 Flash 0731 alternate was removed on 2026-10-25: Tom chose
kyuz0's DeepSeek V4.1 Flash 1017, which Gufo cannot load (it accepts only the
`deepseek4` architecture). Its catalogue rows and Library bytes stay until an
explicit Library retirement.

`gufo-tts` (:8735), `gufo-asr` (:8736) and `gufo-image` (:8737) are on-demand
loopback units with no boot target; `gufo-image` takes the GPU from every text
unit while it runs.

## DeepSeek V4.1 on ds4 (retired)

Tom permanently retired the local DeepSeek bundle on 2026-11-08 (e832663c).
[`../../modules/ds4.nix`](../../modules/ds4.nix) keeps its options for
history, with `services.ds4.enable = false` and no wanted artifacts on either
Strix ([`../../modules/strix-compute.nix`](../../modules/strix-compute.nix)).
Nothing serves `:8732`. Remote DeepSeek API routes in dsh are unaffected.

## Embeddings: the `qwen3-embedding-8b` route

Since 2026-11-10 (Tom: "i m a gufo maximalist") llama-swap on
strix-coordinator also routes `qwen3-embedding-8b` to a Gufo embedding server
([`../../modules/gufo-embedding.nix`](../../modules/gufo-embedding.nix)): Gufo
v0.33.0 (flake input `gufo-embedding`, isolated from the `gufo` input every
other route uses) with the community Qwen3-Embedding-8B extension compiled in
from the vendored snapshot
[`../../pkgs/gufo-extensions/qwen3-embedding`](../../pkgs/gufo-extensions/qwen3-embedding/VENDORED.md).
It serves Qwen's official Q8_0 GGUF (`qwen3-embedding-8b-q8-gguf`) as
`POST /v1/embeddings` (and llama.cpp's `POST /embeddings`): up to 8192 input
tokens per text including the end-of-text token, 4096-dimensional
L2-normalised vectors from last-token pooling. `dimensions` accepts 128, 256,
512 and 768 (Gufo's host rule); other Matryoshka widths are client-side
truncation and renormalisation. There is no `prompt_name`: queries carry the
`Instruct: <task>\nQuery: <text>` prefix themselves; documents go in plain.

It is loaded on demand and swapped like every other route, so it is never
resident beside Flash-Next (Tom, 2026-11-10: "embedder does not stay loaded
besides flash-next ... ideally one embeding endpoint through llama-swap").
Borrow it first (`sudo local-models-borrow --yes`); the launcher refuses a
missing or wrong-sized file.

```console
curl -s http://strix-coordinator:8731/v1/embeddings -H 'content-type: application/json' \
  -d '{"model":"qwen3-embedding-8b","input":["ping"]}'
```

## The `utility` slot

Callers name the stable ID `utility`, never a concrete model. The
request-scoped `utility-model` wrapper
([`../../modules/utility-model.nix`](../../modules/utility-model.nix),
[`../../pkgs/utility-model/utility_model.py`](../../pkgs/utility-model/utility_model.py))
forwards one chat-completions request to `http://strix-coordinator:8731` as
`qwen3.8-flash-next` and returns the answer. `/drain` and `/print` call it
with the same CLI flags as before. The wrapper owns no process and loads
nothing.

## dsh on the NAS

dsh (`pkgs/dsh`, `home/dsh.nix`) is the agent harness; it follows the brain
role to the NAS. Its routes ([`../../pkgs/dsh/config.nix`](../../pkgs/dsh/config.nix)):

- `google/gemini-3.8-flash`, the default (Gemini free tier, one of three AI
  Studio keys per run; [`../free-lanes.md`](../free-lanes.md));
- `gufo/qwen3.8-flash-next` and `gufo/qwen3.8-27b` (the latter only after
  `gufo-switch qwen38-27b`);
- in the hand-run `dsh zen` profile only, OpenCode Zen's free models through
  jiesou's provider plugin (`opencode-zen-free-provider/deepseek-v4.1-flash-free`).

`DSH_ROUTE=<gemini|gemini-pro|gemini-lite|gufo|zen-deepseek|zen-glm>` (and,
since issue 687, `groq`, `groq-oss`, `mistral`, `codestral`, `cohere`,
`nvidia`, `nvidia-deepseek`, `cloudflare`, `cloudflare-deepseek`,
`huggingface`, `cerebras`, `cerebras-oss`, `vercel`; `docs/free-lanes.md`)
picks the
route per run; the QwenCloud route was removed with the account (2026-11-01).

Both local routes use a public dummy bearer. Session-log and plugin-inventory
upload to DeepSeek, DeepSeek sign-in and telemetry are disabled rows in the
policy, and `dsh web` is refused by the wrapper.

## How an artifact reaches a host

The weight plane lives outside Nix. A catalogue row in
[`../../lib/local-models.nix`](../../lib/local-models.nix) gives an artifact an
identity and a pinned provenance record; it does not move a byte.

1. **Library.** `library-fetch` on the NAS
   ([`../../hosts/nas/models.nix`](../../hosts/nas/models.nix)) is the only
   thing that talks to Hugging Face. It fills `/mnt/nas/models/weights/<id>/`
   (exported to the Strix pair at `/mnt/library/weights`) and never deletes.
2. **Wanted set.** Each Strix declares `services.local-models.artifacts`
   ([`../../modules/local-models.nix`](../../modules/local-models.nix)), which
   renders to `/etc/local-models/wanted.json`: everything the host holds,
   and the set prune keeps. The scoped manifest
   `/etc/gufo/27b-q8-wanted.json` borrows one bundle alone (`sudo env LOCAL_MODELS_MANIFEST=… local-models-borrow`).
   A switch describes a set; it transfers nothing.
3. **Borrow.** An operator copies wanted artifacts from the Library into
   `/var/lib/local-models/<id>/`, verified by size and SHA-256, with a
   free-space gate:

   ```console
   sudo local-models-borrow --dry-run   # plan: bytes needed, bytes free, what is missing upstream
   sudo local-models-borrow --yes       # copy + verify from the NAS Library
   ```

4. **Prune.** Borrowing never deletes. The only thing that removes a loaned
   copy is the separate pruner, and it refuses unless the set it recorded at
   `--dry-run` is still the set it sees at `--yes`:

   ```console
   sudo local-models-prune --dry-run
   sudo local-models-prune --yes
   ```

Neither transaction is a service, timer, boot unit or activation hook.
[`../nas/model-archive.md`](../nas/model-archive.md) is the retire/restore
runbook for the Library itself.

## Per-host wanted sets

| Host | Wanted artifacts | Served by |
|---|---|---|
| `strix-coordinator` (and the dormant `strix-worker`'s configuration) | `qwen38-flash-next-gguf`, `qwen38-27b-gguf`, `qwen38-27b-q8-gguf`, `qwen38-27b-dflash2-gguf`, `qwen3-asr-1.7b`, `qwen3-tts-12hz-1.7b-base`, `qwen-image-2.1`, `vibevoice-asr-streaming-7b-bf16`, `qwen3-tts-1.7b-base-q8-0`, `qwen-k2so-midway-b`, `qwen3-tts-tokenizer-f32` (exact lists asserted in `flake.nix`) | Gufo Flash-Next resident at boot, the 27B or 27B Q8 after `gufo-switch`, Gufo ASR, TTS and image on demand; streaming ASR per `call-diarize` run; Qwen speech on demand (`modules/qwen-tts.nix`) |
| `strix-coordinator` only | `qwen3-embedding-8b-q8-gguf` (since 2026-11-10), `hy-memory-30b-a3b-q8-gguf`, `d3-ultra-bf16`, `qwen38-27b-heretic-ara-q8-gguf`, `qwen38-flash-next-abliterated-rocmfp4-gguf` | the Gufo embedding route, on demand through llama-swap; the others as their modules declare |
| `client` | none | — |
| `nas` | none (it holds the Library) | — |

## Running a loaned GGUF by hand

A GGUF that an operator brings back by hand (re-adding its row first, so
`library-fetch` fills the Library) has no server. Both Strix carry
nix-strix-halo's `llama-cpp-rocm` and `llama-cpp-vulkan` commands
([`../../modules/strix-ai.nix`](../../modules/strix-ai.nix)), so an operator
who has borrowed a row starts it in a shell and stops it when done:

```console
llama-server --port 8080 -ngl 999 -m /var/lib/local-models/<id>/<file>.gguf
```

Runtime downloads (`-hf`) are out: the bytes come from the Library or not at
all.

## Other rows

- **Speech.** Qwen3-TTS 1.7B Base Q8 with the `qwen-k2so-midway-b` voice is
  the one TTS model (`modules/qwen-tts.nix`). VibeVoice-ASR-Streaming-7B is the
  one diarization model; `call-diarize` loads it from
  `/var/lib/local-models/vibevoice-asr-streaming-7b-bf16`.
- **MiniMax H3 FL2VA**: Tom accepted its licence on 2026-10-25 and the NAS
  Library holds it. No strix wants it yet: it is 144 GB against 100 GB free on
  strix-coordinator, and Gufo's video support is
  upstream work in progress. `source.gate` has no users now.
- **Mage** rows were retired on 2026-09-30 (sweep F1); [`mage.md`](mage.md)
  keeps the selection record.

## History

- **Halogen** (`modules/halogen.nix`, Peonist's `.hgn` server on `:8731`) was
  the resident engine until 2026-10-23, when Tom ruled "halogen is OUT fullly"
  and #605 replaced it with Gufo. Its NAS Library copies
  (`/mnt/nas/models/weights/halogen-*`) are historical bytes awaiting an
  explicit retirement. [`../gufo-cutover.md`](../gufo-cutover.md) records the
  move.
- On 2026-10-25 Tom ruled that the DeepSeek harness completely replaces the
  Halogen runtime: dsh over Gufo and ds4 became the local agent path.
- **ds4** (`modules/ds4.nix`, kyuz0's `strix-halo-ds4-toolbox` on `:8732`)
  served DeepSeek V4.1 Flash 1017 by hand on strix-worker from 2026-10-25
  until Tom retired local DeepSeek on 2026-11-08. The dual-Strix TP2 rank went
  with the second Strix (#698).

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) — the typed
   catalogue: identity, pinned revision, bytes, hashes.
2. [`../../lib/local-model.nix`](../../lib/local-model.nix) — the endpoints
   and served model ids every consumer uses.
3. [`../../modules/gufo.nix`](../../modules/gufo.nix),
   [`../../modules/gufo-embedding.nix`](../../modules/gufo-embedding.nix) and
   [`../../modules/ds4.nix`](../../modules/ds4.nix) (retired, disabled) —
   the engines;
   [`../../modules/strix.nix`](../../modules/strix.nix) and
   [`../../modules/strix-compute.nix`](../../modules/strix-compute.nix) —
   their declaration on the Strix hosts and the wanted sets.
4. [`../../modules/local-models.nix`](../../modules/local-models.nix) — the
   wanted-set manifest and the borrow transaction;
   [`../../pkgs/local-models-prune.nix`](../../pkgs/local-models-prune.nix)
   — the pruner.
5. [`../../hosts/nas/models.nix`](../../hosts/nas/models.nix) — the Library
   and `library-fetch`.
6. [`model-roster.md`](model-roster.md) — the catalogue as a table.
7. [`../../flake.nix`](../../flake.nix) and `tests/ds4` — assertions pinning
   each host's wanted set and ds4's retirement, so the tables cannot drift
   silently.
