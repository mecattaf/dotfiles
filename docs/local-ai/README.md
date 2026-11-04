# Local AI

The active compute host is strix-coordinator; NAS holds the canonical Library
and interactive dsh sessions. strix-worker is dormant. Gufo and the separate
SuperROC backend share the demand-loaded llama-swap endpoint, one backend at
a time. See [Gufo demand loading](../gufo-demand.md) for the current supervisor
and [the exact modified Flash](../superroc-flash-next.md) for its runtime.

| Engine | Where | Port | Serves | Started by |
|---|---|---|---|---|
| Gufo ([`../../modules/gufo.nix`](../../modules/gufo.nix)) | strix-coordinator, behind llama-swap | 8731 | Stock Flash-Next, stock 27B, 27B Q8 and `qwen3.8-27b-ara` | API model selection; idle unloading |
| SuperROC ([`../../modules/superroc.nix`](../../modules/superroc.nix)) | strix-coordinator, same supervisor | 8731 | `qwen3.8-flash-next-abliterated`, exact kingjones777 ROCmFP4 hcq8-ssmf32 | API model selection; idle unloading |
| ds4 ([`../../modules/ds4.nix`](../../modules/ds4.nix)) | declared on dormant strix-worker | 8732 | historical DeepSeek V4.1 Flash route | unavailable while worker is dormant |

The agent harness that uses them is dsh on the NAS (see [dsh](#dsh-on-the-nas)).
Halogen, the earlier engine, was retired on 2026-10-23 and pi, the earlier
harness, on 2026-10-25; both appear below only as history.

## Gufo Flash-Next on strix-coordinator

[`../../modules/gufo.nix`](../../modules/gufo.nix) runs the native `gufo`
binary for gfx1151 (flake input `gufo`, no container), demand-loaded through
llama-swap. Direct model units are manual diagnostics. Both Strix declare it from one block in
[`../../modules/strix.nix`](../../modules/strix.nix). The default route loads
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
| Not available | `/v1/embeddings` (501), reranking, diarization |

```console
curl -s http://strix-coordinator:8731/v1/models
curl -s http://strix-coordinator:8731/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"ping"}],"max_tokens":16}'
```

strix-worker retains declarations for a future second rank and failover. It
is dormant; these declarations do not establish RDMA or failover readiness.

## The alternate and the switch

The alternate is Qwen3.8-27B (`qwen38-27b-gguf` with the DFlash2 draft, four
sessions, 131072 tokens; or `qwen38-27b-q8-gguf` from the scoped
`/etc/gufo/27b-q8-wanted.json`), served as `qwen3.8-27b` on the same port.
Normal requests select their model ID; llama-swap unloads the previous
backend. The explicit warmer also remains available:

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

## Historical DeepSeek V4.1 declaration on dormant strix-worker

This is retained configuration, not an available service.
[`../../modules/ds4.nix`](../../modules/ds4.nix) declares kyuz0's
`strix-halo-ds4-toolbox` image, pinned by digest, under podman with
`--pull=never`. On strix-worker it is in `single-ssd` mode: the 340.6 GiB Q2
cannot be resident on one 128 GB box, so `ds4-server` streams routed experts
from the local SSD through a 76 GB expert cache (`--ssd-streaming`). DSpark
needs resident experts and is refused in this mode; vision stays off until the
1017 encoder is proven in the image.

| | |
|---|---|
| Base URL | `http://10.42.0.5:8732` (`lib/local-model.nix`'s `ds4` entry) |
| Model id | `deepseek-v4.1-flash` |
| Context | 32768 tokens; Think Max needs at least 393216, so requests get high |
| Admitted from | the NAS (`10.42.0.1`) only, over `enp191s0` |
| Auth | none |

Nothing starts it at boot and nothing automated calls it. Bytes and image are
explicit preparation steps:

```console
sudo podman pull docker.io/kyuz0/strix-halo-ds4-toolbox@sha256:34dec90a…   # the digest in modules/ds4.nix
sudo env LOCAL_MODELS_MANIFEST=/etc/ds4/wanted.json local-models-borrow --dry-run
sudo env LOCAL_MODELS_MANIFEST=/etc/ds4/wanted.json local-models-borrow --yes
sudo systemctl start ds4     # Conflicts= stops the worker's Gufo text units
sudo systemctl stop ds4 && sudo systemctl start gufo-llm
```

The fleet endpoint on strix-coordinator is untouched while ds4 runs. The
coordinator keeps the `tp2` rank shape of the same module for the day both
disks hold the Q2 (each rank needs the full file locally; the TP2 link is TCP
until the image gains a usb4_rdma provider).

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
- `gufo/qwen3.8-flash-next`, `gufo/qwen3.8-27b`,
  `gufo/qwen3.8-27b-ara` and `gufo/qwen3.8-flash-next-abliterated`;
  the selected model loads through llama-swap;
- `ds4/deepseek-v4.1-flash`, only while `ds4.service` runs on strix-worker;
- in the hand-run `dsh zen` profile only, OpenCode Zen's free models through
  jiesou's provider plugin (`opencode-zen-free-provider/deepseek-v4.1-flash-free`).

`DSH_ROUTE=<gemini|gemini-pro|gemini-lite|gufo|qwen-ara|qwen-flash-abliterated|zen-deepseek|zen-glm>` (and,
since issue 687, `groq`, `groq-oss`, `mistral`, `codestral`, `cohere`,
`nvidia`, `nvidia-deepseek`, `cloudflare`, `cloudflare-deepseek`,
`huggingface`, `cerebras`, `cerebras-oss`, `vercel`; `docs/free-lanes.md`)
picks the
route per run; the QwenCloud route was removed with the account (2026-11-01).

Both local routes use a public dummy bearer. Session-log and plugin-inventory
upload to DeepSeek, DeepSeek sign-in and telemetry are disabled rows in the
policy. The stock `dsh web` profile is available for interactive conversation;
Tom's 2026-11-03 decision supersedes the earlier web-profile ban.

Start on the NAS with `DSH_ROUTE=qwen-ara dsh web --no-open`. The model picker
also offers `gufo/qwen3.8-flash-next-abliterated`; selecting it demand-loads
the SuperROC Flash-Next backend through the same llama-swap endpoint. Both modified
models are text-only. Their default routes leave request-level reasoning
effort unset so the server's qualified thinking settings apply.

The current hand-run chat is at <https://nas.tail8dd1.ts.net:8444/>, through
Tailscale Serve to NAS loopback. The browser first opens DSH's private launch
URL to establish its normal signed cookie. See
[the chat runbook](../dsh-local-qwen-chat.md) for the launcher, authentication,
verification receipts and removal of this single Serve listener.

## How an artifact reaches a host

The weight plane lives outside Nix. A catalogue row in
[`../../lib/local-models.nix`](../../lib/local-models.nix) gives an artifact an
identity and a pinned provenance record; it does not move a byte.

1. **Library.** `library-fetch` normally runs on the NAS
   ([`../../hosts/nas/models.nix`](../../hosts/nas/models.nix)) is the only
   thing that talks to Hugging Face. For this acquisition Tom explicitly
   authorized direct Flash downloads on Strix followed by verified NAS copies. It fills `/mnt/nas/models/weights/<id>/`
   (exported to the Strix pair at `/mnt/library/weights`) and never deletes.
2. **Wanted set.** Each Strix declares `services.local-models.artifacts`
   ([`../../modules/local-models.nix`](../../modules/local-models.nix)), which
   renders to `/etc/local-models/wanted.json`: everything the host holds,
   and the set prune keeps. The scoped manifests `/etc/ds4/wanted.json`,
   `/etc/gufo/tp2-q8-wanted.json` and `/etc/gufo/27b-q8-wanted.json` borrow
   one bundle alone (`sudo env LOCAL_MODELS_MANIFEST=… local-models-borrow`).
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
| `strix-coordinator`, `strix-worker` | `qwen38-flash-next-gguf`, `qwen38-27b-gguf`, `qwen38-27b-q8-gguf`, `qwen38-27b-dflash2-gguf`, `qwen3-asr-1.7b`, `qwen3-tts-12hz-1.7b-base`, `qwen-image-2.1`, `vibevoice-asr-streaming-7b-bf16`, `qwen3-tts-1.7b-base-q8-0`, `qwen-k2so-midway-b`, `qwen3-tts-tokenizer-f32` (exact lists asserted in `flake.nix`) | Gufo routes demand-load on the coordinator; worker is dormant, Gufo ASR, TTS and image on demand; streaming ASR per `call-diarize` run; Qwen speech on demand (`modules/qwen-tts.nix`) |
| `strix-coordinator` only | `qwen38-27b-heretic-ara-q8-gguf`, `qwen38-flash-next-abliterated-rocmfp4-gguf`, `d3-ultra-bf16` | Gufo ARA, SuperROC Flash and D3, through the same demand supervisor |
| `strix-worker` only | `deepseek-v41-flash-1017-q2-gguf` (via `services.ds4.wanted`), `qwen38-flash-next-q8-gguf` | ds4, by hand; `gufo-tp2` with Q8. The coordinator's disk cannot hold either (D-A) |
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
  strix-coordinator and 61 GB on strix-worker, and Gufo's video support is
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
  Halogen runtime: dsh over Gufo and ds4 is the local agent path.

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) — the typed
   catalogue: identity, pinned revision, bytes, hashes.
2. [`../../lib/local-model.nix`](../../lib/local-model.nix) — the endpoints
   and served model ids every consumer uses.
3. [`../../modules/gufo.nix`](../../modules/gufo.nix) and
   [`../../modules/ds4.nix`](../../modules/ds4.nix) — the two engines;
   [`../../modules/strix.nix`](../../modules/strix.nix) and
   [`../../modules/strix-compute.nix`](../../modules/strix-compute.nix) —
   their declaration on the Strix pair and the wanted sets.
4. [`../../modules/local-models.nix`](../../modules/local-models.nix) — the
   wanted-set manifest and the borrow transaction;
   [`../../pkgs/local-models-prune.nix`](../../pkgs/local-models-prune.nix)
   — the pruner.
5. [`../../hosts/nas/models.nix`](../../hosts/nas/models.nix) — the Library
   and `library-fetch`.
6. [`model-roster.md`](model-roster.md) — the catalogue as a table.
7. [`../../flake.nix`](../../flake.nix) and `tests/ds4` — assertions pinning
   each host's wanted set and the ds4 shape, so the tables cannot drift
   silently.
