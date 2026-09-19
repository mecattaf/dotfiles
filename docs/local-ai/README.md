# Local AI

The fleet runs one resident inference server and a Library of loanable model
artifacts. Every claim on this page names the Nix file that decides it.

## The resident server: Halogen Flash on the worker

[`../../modules/halogen.nix`](../../modules/halogen.nix) runs
`ghcr.io/peonist-ai/halogen-flash-server` (a pinned OCI image, under podman).
Both Strix Halo twins declare it, with the Qwen3.8-27B alternate, from one
block in [`../../modules/strix.nix`](../../modules/strix.nix) (Tom,
2026-09-16: both models on both devices). On the worker Flash is resident from
boot and is the fleet endpoint below; on the coordinator nothing starts at boot
(see [Halogen on the coordinator](#halogen-on-the-coordinator)). It loads Qwen3.8-Flash-Next in
Peonist's proprietary `.hgn` format from
`/var/lib/local-models/halogen-qwen38-flash-next` — the catalogue row
`halogen-qwen38-flash-next`, loaned there from the NAS Library. Nothing else
loads those bytes: not llama.cpp, not vLLM, not transformers.

| | |
|---|---|
| Base URL | `http://worker:8731` (`worker` resolves to `10.42.0.5` from every host; wired LAN only) |
| Model id | `halogen-qwen3.8-flash-next` — a label; a request naming another id is not rejected |
| Endpoints | `POST /v1/chat/completions` (streaming and non-streaming, tool calls, `image_url` content parts), `POST /v1/responses`, `POST /v1/completions`, `GET /v1/models`, `GET /health` (JSON; the liveness and discovery probe) |
| Auth | none |
| Reasoning budget | the token budget covers thinking; default `max_tokens` 8192, cap 65536; three budget spellings are accepted, but two spellings with different values is a 400 |
| Not available | `/v1/embeddings`, reranking, audio, image generation, hot reload, a second resident model |

The vision tower is part of the bundle, so OCR and image reading are requests
to this same server with `image_url` content parts.

```console
curl -s http://worker:8731/health
curl -s http://worker:8731/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"halogen-qwen3.8-flash-next","messages":[{"role":"user","content":"ping"}]}'
```

Anything that takes an inference base URL reads it from a `*_INFERENCE_URL`
variable defaulting to `http://worker:8731`; the override is there for a
hand-run server (below) or the coordinator's operator-started Halogen, not for
a second resident server.

## The alternate and the switch

`halogen-qwen38-27b` is served by `ghcr.io/peonist-ai/halogen` (halogen-server
0.1.4, pinned by digest in `modules/strix.nix`) as `podman-halogen-qwen38-27b`,
on the same port and launch shape, text only. Unlike Flash it has no
healthcheck binary and no server-side default-budget knob: its default
`max_tokens` is 8192 and thinking counts against it, so an agentic client must
send `max_tokens` itself or risk an empty reply with `finish_reason: "length"`.
The units carry mutual `Conflicts=`, so one engine is resident at a time on a
host:

```console
sudo halogen-switch qwen38-27b   # stop Flash, cold-load the 27B
sudo halogen-switch flash        # and back
sudo halogen-switch off          # stop every Halogen unit, releasing the GPU
```

## Halogen on the coordinator

The coordinator carries the same two containers, the same bundles in its wanted
set and `amdgpu.gttsize=126976`, but `services.halogen.autoStart = false`: it
is Tom's desktop and also runs Qwen TTS, Parakeet, the ~17.6 GB streaming ASR
and live agent sessions, and upstream sizes Flash as leaving roughly 12 GB free
on a 128 GB box. Before starting either engine there, check that nothing else
holds the GPU (`amdtop`, `mem_info_gtt_used`, running `call-diarize` or TTS),
then `sudo halogen-switch flash|qwen38-27b`, and `sudo halogen-switch off`
when done. Two memory bounds apply there only: Flash's KV pool is 262144
positions (~28 GB, its floor) and the 27B's prompt cache is a fixed 8 GiB
(`HALOGEN_CACHE_MB=8192`) instead of auto-sizing from free memory. It answers on `http://coordinator:8731` (admitted on `wlp192s0`).
A coordinator switch defers while a Halogen unit is active (update-adopt gate
`halogen-units`). The `utility` slot does not move: it stays on the worker.

## The `utility` slot

Callers name the stable ID `utility`, never a concrete model. The
request-scoped `utility-model` wrapper
([`../../pkgs/utility-model/utility_model.py`](../../pkgs/utility-model/utility_model.py),
installed on the coordinator only) forwards one chat-completions request to
the worker's halogen server and returns the answer. `/drain` and `/print`
call `utility-model` with the same CLI flags they always have. The wrapper
owns no process and loads nothing; the server on the worker is resident, and
the coordinator's own Halogen units are never its target.

## How an artifact reaches a host

The weight plane lives outside Nix. A catalogue row in
[`../../lib/local-models.nix`](../../lib/local-models.nix) gives an artifact an
identity and a pinned provenance record; it does not move a byte.

1. **Library.** `library-fetch` on the NAS
   ([`../../hosts/nas/models.nix`](../../hosts/nas/models.nix)) is the only
   thing that talks to Hugging Face. It fills `/mnt/nas/models/weights/<id>/`
   (exported to the twins at `/mnt/library/weights`) and never deletes.
2. **Wanted set.** Each twin declares `services.local-models.artifacts`
   ([`../../modules/local-models.nix`](../../modules/local-models.nix)), which
   renders to `/etc/local-models/wanted.json`. A switch describes the set;
   it transfers nothing.
3. **Borrow.** An operator copies wanted artifacts from the Library into
   `/var/lib/local-models/<id>/`, verified by size and SHA-256, with a free-space
   gate:

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
| `worker` | `halogen-qwen38-flash-next`, `halogen-qwen38-27b` | `modules/halogen.nix`; Flash resident at boot, the 27B after `halogen-switch qwen38-27b` |
| `coordinator` | `halogen-qwen38-flash-next`, `halogen-qwen38-27b`, `fara15-9b-q8-0`, `fara15-9b-mmproj-bf16`, `vibevoice-asr-streaming-7b-bf16`, `openwakeword-baker-compat-v051`, `openwakeword-alexa-v051`, `qwen3-tts-1.7b-base-q8-0`, `qwen-k2so-midway-b`, `parakeet-tdt-0.6b-v3-onnx`, `qwen3-tts-tokenizer-f32` | Halogen only after `halogen-switch`; FARA 9B on demand on loopback 8732 (`modules/fara-browser-model.nix`, restored 2026-09-19, see [fara-restore-2026-09-19.md](fara-restore-2026-09-19.md)); streaming ASR per `call-diarize` run; Qwen speech on demand (`modules/qwen-tts.nix`); Parakeet resident (`home/speech.nix`) |
| `client` | `openwakeword-baker-compat-v051`, `openwakeword-alexa-v051` | the wake listener (`home/speech.nix`) |
| `nas` | none (it holds the Library) | — |

## Running a loaned GGUF by hand

Library rows without a declared consumer (the text embedder) have no server.
Both twins carry nix-strix-halo's `llama-cpp-rocm` and `llama-cpp-vulkan`
commands ([`../../modules/strix-ai.nix`](../../modules/strix-ai.nix)), so an
operator who has borrowed a row starts it in a shell and stops it when done:

```console
llama-server --port 8080 --embedding -ngl 999 \
  -m /var/lib/local-models/qwen3-embedding-8b-q8-0/Qwen3-Embedding-8B-Q8_0.gguf
```

Point the caller at it through its `*_INFERENCE_URL` override. Runtime
downloads (`-hf`) are forbidden by assertion: the bytes come from the Library
or not at all. There is no embeddings server until an operator starts one.

## Other rows

- **Speech.** Qwen3-TTS 1.7B Base Q8 with the `qwen-k2so-midway-b` voice is
  the one TTS model (`modules/qwen-tts.nix`). VibeVoice-ASR-Streaming-7B is the
  one diarization model; `call-diarize` loads it from
  `/var/lib/local-models/vibevoice-asr-streaming-7b-bf16`.
- **Mage (Mage-Flow Turbo, Mage-Flow Edit Turbo, Mage-VL)** are loanable
  Library artifacts with their own upstream runtimes and no server on this
  fleet. [`mage.md`](mage.md) records the selected Mage snapshots and their
  invocation contract.
- **Voxtype** (streaming dictation, `parakeet-unified-en-0.6b`) is not a
  catalogue artifact: `home/voxtype.nix` lets the tool own its own model
  directory on the coordinator.

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) and
   [`../../lib/mage-models.nix`](../../lib/mage-models.nix) — the typed
   catalogue: identity, pinned revision, bytes, hashes.
2. [`../../modules/halogen.nix`](../../modules/halogen.nix) — the Halogen
   server; [`../../modules/strix.nix`](../../modules/strix.nix) — its
   declaration on both twins and the twins' wanted sets.
3. [`../../modules/local-models.nix`](../../modules/local-models.nix) — the
   wanted-set manifest and the borrow transaction;
   [`../../pkgs/local-models-prune.nix`](../../pkgs/local-models-prune.nix)
   — the pruner.
4. [`../../hosts/nas/models.nix`](../../hosts/nas/models.nix) — the Library
   and `library-fetch`.
5. [`model-roster.md`](model-roster.md) — the catalogue as a table.
6. [`../../flake.nix`](../../flake.nix) — assertions pinning each host's
   wanted set, so the table cannot drift silently.
