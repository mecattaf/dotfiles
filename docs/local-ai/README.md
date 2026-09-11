# Local AI

The fleet runs one inference server and a Library of loanable model artifacts.
Every claim on this page names the Nix file that decides it.

## The one server: Halogen Flash on the worker

[`../../modules/halogen.nix`](../../modules/halogen.nix) runs
`ghcr.io/peonist-ai/halogen-flash-server` (a pinned OCI image, under podman) on
the worker, the second Strix Halo twin. It loads Qwen3.8-Flash-Next in
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
| Not available | `/v1/embeddings`, reranking, audio, image generation, hot reload, a second model |

The vision tower is part of the bundle, so OCR and image reading are requests
to this same server with `image_url` content parts.

```console
curl -s http://worker:8731/health
curl -s http://worker:8731/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"halogen-qwen3.8-flash-next","messages":[{"role":"user","content":"ping"}]}'
```

Anything that takes an inference base URL reads it from a `*_INFERENCE_URL`
variable defaulting to `http://worker:8731`; the override is there for a
hand-run `llama-server` (below), not for a second declared server.

## The `utility` slot

Callers name the stable ID `utility`, never a concrete model. The
request-scoped `utility-model` wrapper
([`../../pkgs/utility-model/utility_model.py`](../../pkgs/utility-model/utility_model.py),
installed on the coordinator only) forwards one chat-completions request to
the worker's halogen server and returns the answer. `/drain` and `/print`
call `utility-model` with the same CLI flags they always have. The wrapper
owns no process and loads nothing; the server on the worker is always
resident.

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
| `worker` | `halogen-qwen38-flash-next` | `modules/halogen.nix`, always resident |
| `coordinator` | `qwen36-35b-a3b-mtp-ud-q8-k-xl`, `gemma4-12b-it-q8-0`, `gemma4-12b-it-mtp-q8-0`, `fara15-9b-q8-0`, `fara15-9b-mmproj-bf16` | nothing declarative — an operator's `llama-server` |
| `nas` | none (it holds the Library) | — |

## Running a loaned GGUF by hand

The coordinator's small models have no declared server. Both twins carry
nix-strix-halo's `llama-cpp-rocm` and `llama-cpp-vulkan` commands
([`../../modules/strix-ai.nix`](../../modules/strix-ai.nix)), so an operator
who has borrowed a row starts it in a shell and stops it when done:

```console
llama-server --port 8080 \
  -m /var/lib/local-models/qwen36-35b-a3b-mtp-ud-q8-k-xl/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
  -c 32768 -ngl 999

llama-server --port 8080 \
  -m /var/lib/local-models/fara15-9b-q8-0/Fara1.5-9B-Q8_0.gguf \
  --mmproj /var/lib/local-models/fara15-9b-mmproj-bf16/mmproj-Fara1.5-9B-bf16.gguf -ngl 999
```

Point the caller at it through its `*_INFERENCE_URL` override. Runtime
downloads (`-hf`) are forbidden by assertion: the bytes come from the Library
or not at all. The same pattern covers the embedders — there is no embeddings
server until an operator starts one with `--embedding`.

## Other rows

- **Speech (VibeVoice-ASR, VibeVoice-Large, the Qwen2.5 tokenizer)** and
  **Mage (Mage-Flow Turbo, Mage-Flow Edit Turbo, Mage-VL)** are loanable
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
2. [`../../modules/halogen.nix`](../../modules/halogen.nix) — the one server.
3. [`../../modules/local-models.nix`](../../modules/local-models.nix) — the
   wanted-set manifest and the borrow transaction;
   [`../../pkgs/local-models-prune.nix`](../../pkgs/local-models-prune.nix)
   — the pruner.
4. [`../../hosts/nas/models.nix`](../../hosts/nas/models.nix) — the Library
   and `library-fetch`.
5. [`model-roster.md`](model-roster.md) — the catalogue as a table.
6. [`../../flake.nix`](../../flake.nix) — assertions pinning each host's
   wanted set, so the table cannot drift silently.
