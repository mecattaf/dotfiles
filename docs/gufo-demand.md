# Gufo demand loading

The public endpoint remains `http://strix-coordinator:8731`. The standard
NixOS llama-swap service owns it, while Gufo children listen on loopback
ports assigned from 18731. No model is preloaded. Printing and drain keep
their existing `utility-model` interface and wait for a cold load as needed.

This follows [Federico's configuration](https://github.com/fedeizzo/nix-dotfiles/blob/main/modules/services/ai-workflows/llama-swap/llama-swap.n.nix):
Gufo's upstream `mkGufoServe` helper renders commands; text/image models have
600-second idle TTLs and Gufo TTS/ASR have 120-second TTLs. Active requests,
including streams, prevent idle unloading. The upstream default swaps one
model at a time across modalities. No custom supervisor or model scheduler
is added.

The initial roster contains Flash-Next, 27B Q4, 27B Q8, Gufo Base TTS with the
existing reference voice, ASR and Qwen-Image. The Q8 route is
`qwen3.8-27b-q8`; llama-swap sends Gufo its actual `qwen3.8-27b` wire name.
This adds a Gufo TTS API choice; the existing production speech queue still
uses its separately qualified qwentts.cpp voice.

`gufo-switch flash|qwen38-27b|qwen38-27b-q8` explicitly warms a model through
llama-swap. Ordinary API requests select their model without this command.
`gufo-switch off` stops the endpoint and its children. Direct Gufo units
remain manual diagnostic paths and conflict with the proxy and TP2 as
appropriate; none starts at boot.

Routine monitoring uses `/health`, `/running` and `/v1/models`. These do not
start a backend or refresh its TTL. An empty running list is healthy sleep,
not a failed service. `/upstream/<model>/...` intentionally starts that model;
handwriting's explicit preflight uses it, with a cold-load timeout.

## Add a deployment for an existing catalog artifact

Put a row under `services.gufo.models` in the host's Gufo configuration (the
shared fleet defaults are in `modules/strix.nix`). For example, this adds a
short-context 27B profile using existing borrowed weights:

```nix
services.gufo.models."qwen27-short" = {
  artifact = "qwen38-27b-gguf";
  modality = "llm";
  mmproj = "mmproj-BF16.gguf";
  dflashArtifact = "qwen38-27b-dflash2-gguf";
  serve = {
    context = 32768;
    sessions = 1;
    think = "off";
    maxTokens = 8192;
  };
  idleSeconds = 600;
};
```

The key is the public API model ID and, by default, Gufo's wire name. Set
`servedModelName` only when an existing wire name must differ. `modality`
accepts `llm`, `tts`, `asr`, `image` or `video`, subject to the pinned Gufo
engine supporting that model. `serve` contains the upstream `mkGufoServe`
options; paths, identity and backend ports are generated.

The row automatically produces:

- A standard llama-swap model entry, loopback backend and positive idle TTL.
- A command rendered with upstream `mkGufoServe`, preceded by the existing
  catalog-size checks.
- Its full `/etc/local-models/wanted.json` requirements: target, draft/support
  artifacts, `extraArtifacts`, and named voice artifacts. Service
  requirements are unioned once with explicit wants, so shared bundles are
  listed only once.
- `/v1/models` discovery metadata and model-aware routing at the same API URL.

Do not add a separate wanted-list entry, systemd unit or shell command. New
rows merge with the initial roster. `idleSeconds` defaults to 600 for
text/image/video and 120 for TTS/ASR. `mmproj` and `mtp` are paths relative to
`artifact`; DFlash2 and DSpark use catalog IDs in `dflashArtifact` and
`dsparkArtifact`. Named voices use
`voices.<name> = { artifact = "<catalog-id>"; wav = "<relative.wav>"; text = "<relative.txt>"; };`.
Their artifacts are included in the wanted set automatically. `extraArtifacts`
is for any additional required bundles.

## Add new model bytes

First add the artifact to `lib/gufo-models.json`, following a neighboring
entry's pinned source revision, files, sizes and hashes. That catalog is
imported by `lib/local-models.nix`; it is the one byte-level definition shared
by the NAS Library and the compute host. See [the model-store runbook](nas/model-archive.md)
for its archive/restore conventions. Then add the deployment row referencing
that catalog ID. Unknown IDs are rejected during Nix evaluation.

After review and deployment of those declarations, run `sudo systemctl start
library-fetch` on NAS to acquire newly declared remote artifacts into the
Library. On compute, inspect `sudo local-models-borrow --dry-run`, then run
`sudo local-models-borrow --yes` to explicitly copy and verify the required
loans. Activation and service startup never download, copy or prune model
bytes. A missing or wrong-sized file refuses startup and names the borrow
command.

Check the public `/v1/models` listing, send an explicit request naming the
new deployment, and verify it disappears from `/running` after its idle TTL.
Adding a row exposes the API route; clients with a separate allowlist (such
as DSH's bounded model picker) still need to opt that model in there. The
mutable Substrate `models.toml` remains runtime data and is not overwritten
by this configuration.

This configuration does not qualify dormant-worker or RDMA operation. TP2,
ds4 and direct modality units conflict with llama-swap so they cannot compete
for its GPU memory or public port.
