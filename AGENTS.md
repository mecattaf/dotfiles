The fleet is mono-model. Its one inference server is Halogen Flash —
Qwen3.8-Flash-Next in Peonist's proprietary `.hgn` format — running on the
worker at `http://worker:8731` via `modules/halogen.nix`: a pinned OCI image
run by podman, with the weights loaned from the NAS Library into
`/var/lib/local-models/halogen-qwen38-flash-next`. It is OpenAI-compatible
(`/v1/chat/completions` streaming and non-streaming with tool calls,
`/v1/responses`, `/v1/completions`, `/v1/models`, `GET /health` as the
liveness and discovery probe), carries the vision tower, so OCR and image
reading go through it too, and needs no authentication. The model id is
`halogen-qwen3.8-flash-next`; a request naming another id is not rejected.
A second Halogen engine, halogen-server with Qwen3.8-27B, is declared on the
same worker as `services.halogen.alternates.qwen38-27b`: same port, same launch
shape, never resident together with Flash (the units conflict), started only by
an operator's `halogen-switch qwen38-27b` and put back with `halogen-switch
flash`. Flash is the everyday model; the 27B is the alternate.
There is no `/v1/embeddings`, no reranking, no audio, no image generation, no
hot reload and no second model. The token budget covers thinking: default
`max_tokens` 8192, cap 65536. Stable diffusion is outside this LLM route.

**The NPU path is decommissioned — permanently, 2026-08-29.** FastFlowLM (`flm`)
is no longer installed on any host, and the XDNA2 NPU is not an inference target
on either Strix Halo twin. Both twins now boot with `amd_iommu=off`, which is by
itself enough to make the old NPU path unbootable; this is a decommission, not a
pause. Do not add a `flm` invocation, an `flm serve` unit, or an NPU backend row
back.

**The `utility` slot forwards to halogen.** The stable ID `utility` resolves to
the worker's Halogen Flash server, and the request-scoped `utility-model`
wrapper — installed on the coordinator only — forwards a single
chat-completions request to it over the wired LAN. `/drain` and `/print` dial
that seam under the same name and with the same CLI flags as before. What must
never come back is an NPU-backed utility deployment; the slot itself is live.

The small GGUF models the fleet keeps — `qwen36-35b-a3b-mtp-ud-q8-k-xl`,
`gemma4-12b-it-q8-0` with its MTP head, `fara15-9b-q8-0` with its projector —
and the specialised rows (the Qwen3 text and VL embedders, VibeVoice speech,
Mage-Flow and Mage-VL) are NAS-Library artifacts. An operator loans them onto
a host with `local-models-borrow` and, for the GGUFs, serves them by hand with
`llama-server` from nix-strix-halo's `llama-cpp-rocm` / `llama-cpp-vulkan`
commands. The sole task-specific exception is FARA 1.5 9B on coordinator: the
on-demand `modules/fara-browser-model.nix` user service listens on loopback
8732 while `fara-browser` needs it. It uses already-loaned weights and is not
a second resident fleet model. Other small models have no declarative service,
timer or proxy row.
Embeddings in particular have no server behind them until an operator starts
one.

Out, and not to be reintroduced: dual-node inference of any kind (the
Thunderbolt and direct 5GbE rails between the twins no longer exist; the
worker is wired-only on `enp191s0` at `10.42.0.5`, with no wifi, no compositor
and no VNC), the flashnext / flashnix / vLLM-fork projects, DS4, GLM, the
dense big models (Qwen3.8-27B, Qwen3.6-27B, Gemma 4 31B, Fara 27B), the
Qwen3-VL OCR rows and the uncensored candidates. A new engine is a new server
module beside `modules/halogen.nix`, or it does not serve.

The weight plane lives outside Nix. `hosts/nas/models.nix`'s `library-fetch`
is the only thing that talks to Hugging Face; it fills the canonical NAS
Library and never deletes. A host's wanted set is declared in Nix and rendered
to `/etc/local-models/wanted.json`, but activation moves no bytes:
`sudo local-models-borrow --dry-run|--yes` copies and verifies wanted
artifacts from the Library into `/var/lib/local-models`, and
`sudo local-models-prune --dry-run|--yes` is the only thing that deletes a
loaned copy, and only when the set it computed has not changed underneath it.
`docs/nas/model-archive.md` is the retire/restore runbook.

**Shared browser desktop (2026-09-12).** Coordinator keeps `myDisplay.enable =
false`: no physical Niri/greetd session. `modules/browser-desktop.nix` supplies a
separate headless Sway seat with WayVNC on loopback and stock noVNC served by
Caddy at `http://browser.internal` on BE550. This exception is coordinator-only;
worker and NAS remain without compositor/VNC. `fara-browser` uses Microsoft's
pinned FARA loop against that noVNC canvas, ordinary installed Chrome profiles,
and one task at a time. The house `fara-browser` skill documents profile/account
selection, human keyring unlock, takeover, replay and task-window cleanup.
