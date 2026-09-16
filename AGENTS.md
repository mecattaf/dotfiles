**Runtime isolation (2026-09-16 incident).** Tests and experiments that source
shell-script fragments, clean runtime directories, or launch test compositors
must run through `runtime-test -- <command> [args...]` (implemented in
`home/dot_local/bin/runtime-test`). It masks the live `/run/user` tree even if
the test hardcodes its path; it leaves checkout files writable. If bubblewrap
is unavailable, stop that test rather than silently running it on live sockets.
Never source script fragments selected by an unbounded text range: extract only
the intended function and inspect it first. A September 16 smoke test sourced
cleanup code along with a function and deleted the live user-service sockets.
Do not suppress unexpected coredumps or unit failures to make tests look healthy.

The fleet's resident language-model server is Halogen Flash —
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

**Speech decision (2026-09-14, latest correction).** Use Qwen3-TTS 1.7B
Base Q8 through ServeurpersoCom/qwentts.cpp, with ONE K-2SO reference voice.
Tom rejected moving forward with CustomVoice, the character/personality project,
and multiple distilled or emotional voice profiles. Preserve completed research
as history; do not apply its personality instructions or build tone switching.
Use as much suitable material from across the supplied sub-three-minute montage
as remains reliable, rather than defaulting to the opening eight seconds.
Reference audio stays at its original speed. Validate longer generated readings
and preserve the liked baseline while testing a broader single reference. Tom
reported roughly seven to eight bangs in the expanded 86-second-bank demo and
wanted a cleaner midway. He subsequently accepted midway B after listening to
the complete 344-word reading and reported no bangs. B is now the active local
profile: a 44.02-second identity bank spanning six scenes and a 25.20-second
matched prefix with a quiet tail. The original favorite remains the comparison
baseline. Enrollment and fleet activation are separate; see the integration record below.
Word accuracy is insufficient: inspect repeated onset artifacts and listen to
quality feedback before treating a broader reference as an improvement.
All LLM inference for this speech/intake flow, including Gemma or a local router,
runs on the coordinator, never the laptop. The laptop owns wake detection, cue,
capture/transport and playback only. TTS and transcription-model inference run
on the coordinator GPU; preparation and
independent CPU transcription checks are explicitly labeled. The separately
authorized lightweight wake detector runs on the client CPU or Intel NPU. The ASUS Zenbook (`client`)
plays the returned audio. Speech weights follow NAS Library/explicit borrowing.
`modules/qwen-tts.nix` owns on-demand synthesis, separate from Halogen; it idles
out and has no boot target. Deterministic text chunks are stitched into one WAV.
The human is **Tom**; use his name naturally in assistant-written addresses,
without rewriting quoted documents or verbatim transcripts.
Ordinary VibeVoice ASR and streaming diarized ASR remain separate evaluation
tracks. The newly requested hotword research is a separate client input/control
pipeline: lightweight wake detection on the Zenbook, not another TTS model or
personality. Prioritize detection responsiveness and reliable waking; CPU usage,
heat and fan noise are secondary. The client is always plugged in. Tom clarified
that he deliberately restored brightness during tests: brightness is not an
acceptance gate or a reason to pause detector comparison. Leave his display
controls alone; listening should work at any brightness while the OS is awake.
If a dark-display check is needed, F10 uses brightness zero with displays enabled,
not DPMS power-off or suspend. Tom selected “Alexa” with upstream openWakeWord
on CPU. Use the original listening nudge after accepted wake and capture readiness.
The Niri Shift+F9 call recorder must inhibit and receive listener shutdown
acknowledgement before capture starts; clear all queued audio on entry and exit.
`pkgs/speech-wake` implements the explicit client input session;
`home/speech.nix` owns its declarative user service.
Research Intel Meteor Lake NPU support only when an existing
wake-word implementation is documented. Scott Baker's existing openWakeWord
CPU/NPU implementation qualifies: Tom explicitly authorized adapting its existing
path to Meteor Lake/NixOS and testing it, despite its Panther Lake/Ubuntu example.
Do not discard it solely for that platform difference; avoid a new detector/model
port from scratch. Keep initial compatibility tests isolated and use saved audio
before enabling an always-on microphone. Compare the working NPU route against
the best practical CPU implementation, not only the same code on CPU: Tom wants
the best complete tool for fast, reliable waking, with quiet operation secondary.
This Intel client investigation does not reopen the retired AMD NPU path.
No wake listener is activated by the research. Call transcription must suppress
wake detection, per Tom's Mykonos annotations.

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
separate on-demand headless Sway seat with WayVNC on loopback and stock noVNC
served by Caddy at `https://browser.internal` on BE550. The lightweight launcher
starts at boot; Sway, WayVNC and Chrome do not. Manual sessions stop five minutes
after the last viewer disconnects; active FARA tasks keep their session alive
and release it on completion/cancellation unless a manual session remains. This exception is coordinator-only;
worker and NAS remain without compositor/VNC. `fara-browser` uses Microsoft's
pinned FARA loop against that noVNC canvas, ordinary installed Chrome profiles,
and one task at a time. The house `fara-browser` skill documents profile/account
selection, human keyring unlock, takeover, replay and task-window cleanup.
`chrome-stream` (same module) is the lighter path: headless Chrome's CDP
screencast in a viewer page, bound to loopback and tunnelled to the client
over `ssh -L`.

**Raw dotfiles come from `~/mecattaf/dotfiles`, not from the flake you switch
from (#313).** Every out-of-store link (`home/home.nix` `link`, herdr, nvim)
points into that checkout. Bring the branch there (ff-merge or `pull
--ff-only`) before `nixos-rebuild switch`, even when switching from a worktree.
`raw-dotfiles-guard` (`home/raw-dotfiles-guard.nix`) fails the Home Manager
activation, before any file is written, when a user unit's
`%h/.local/bin/<program>` is missing from that checkout.


**Handwriting intake (2026-09-14).** `handwriting.internal` is the private
annotation menu, declared by `modules/handwriting-annotation.nix`: NAS DNS,
coordinator Caddy and a CPU-only service. Preserve `/var/lib/handwriting-annotation`
and its append-only writer/model-review history across updates. Model-assisted
resolutions are not writer labels. Huion sources arrive in `~/Paper/inbox`;
`~/Paper/intake` is the printing route. Use the existing Halogen Flash for serial
OCR with thinking explicitly off. `docs/handwriting-intake.md` records the
recipe, correction-evidence rules and real-Huion commissioning boundary. Do not
reseed live review state or treat stable legacy capture files as proof of device
page completeness.

**Speech integration (2026-09-14).** Alexa/openWakeWord on client CPU is the
selected wake path. Direct `parakeet-rs` 0.3.7 with Parakeet TDT v3 ONNX and
MIGraphX runs on the coordinator; Voxtype and its virtual-microphone relay are
retired from the configuration. There is no Gemma/router layer in the daily
flow. Gemma E4B/12B and both VibeVoice ASR tracks remain research artifacts.
`home/speech.nix` declares the resident coordinator transcription unit and client
wake unit. No service startup downloads models. Use the NAS manifests and explicit
`local-models-borrow` transactions documented in `docs/speech-operations.md`.

Alexa creates a fresh Claude Opus Herdr session using a fixed appended system
prompt that enables speech publication. The shared `/speak` skill publishes
visible Markdown files in `~/Speech/intake`; the daemon synthesizes and plays
through the client during 06:00–24:00, matching paper working hours. Publishing a
queue file is not evidence it was heard: consult playback receipts. Session
launch records the fixed system-prompt hash. Do not repair speech behavior by
pasting follow-up instructions into the conversation.

Native Herdr client hold-Space invokes `speech-dictate` on the client, waits for
capture readiness and the original cue, streams PCM to coordinator, and pastes
the result into the originating pane without Enter. Tap-Space remains ordinary
input. Media controls do not cancel recording; editing keys, Escape, focus or
application changes, call recording and playback do. Kitty protocols are used by
Herdr itself: no dedicated kitten, herdr-kitten dependency, GTK/quickshell recording
overlay or client transcription model. New speech windows use the native projector
with a client-scoped pane target. Keep the Herdr server's `X-SwitchMethod=keep-old`
protection: deployment must not kill live PTYs. Existing client processes need a
new projector launch to load a changed binary.

The original montage, accepted midway B enrollment and evaluation outputs are
preserved on NAS; superseded models have not been deleted. See
`docs/mykonos-overnight-integration.md` for the rollout/acceptance record, rather
than inferring activation from these declarations.

**Speech cleanup (2026-09-15).** Use functional speech names, never the idea’s
location as a product/service name. Hands-free follow-on conversation routing is
explicitly dropped. Keep supported implementation and tests in dotfiles; delete
superseded experimental code rather than archiving it on NAS. Keep listening
evidence and canonical model weights separately. Parakeet is independently
declared and remains durable after Voxtype removal.
