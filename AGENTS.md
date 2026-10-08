**Claude seats (2026-09-22).** Two Claude Code logins live on the strix
and nowhere else: `cc` is `~/.claude` (the personal Claude Max login, config file
`~/.claude.json`), `cc2` is `~/.claude-work` (the leger.run Claude Max login,
config file `~/.claude-work/.claude.json`), selected only by `CLAUDE_CONFIG_DIR`
in the fish launchers (`home/dot_config/fish/config.fish`). Both share skills and writable settings at
`~/.local/state/claude/settings.json`; no model or effort is pinned by Nix.
The initializer preserves existing choices and never resets them on activation; login, history, sessions and trust are per seat, so a
session id resumes only on the seat and from the cwd that created it
(`claude-sessions` fans out over the seats). Claude never saves workspace trust
for `$HOME`, so the launchers move into `$CLAUDE_ENVELOPE` (default `~/today`)
when typed from `~`; never start a seat in the home directory. Logins are hand
`/login`s, never a delivered secret (the old claude-credentials seed was removed
this day). `seats` reads its peer cache from `~/.local/state/tally-rewrite/meters`
(the directory name outlives Tally, which was removed on 2026-09-30).

**Scheduled work (Tom, 2026-09-30).** No scheduled agent work is declared in dotfiles. Silent-hours releases (paper 06:05, speech 06:05) stay. Reactive triggers (a Huion scan drops → process when there is bandwidth) are fine. A midnight script that moves jsonl files to the NAS is out. Everything scheduled comes from the factory (substrate).

The one named exception is box upkeep, which is not agent work. These are the
only clocks dotfiles may declare (sweep 2026-09-30, D40–D51); anything else is a
hand-run service, a path/udev/session trigger, or a factory schedule:

| # | Unit(s) | Hosts | Declared in |
|---|---|---|---|
| D41 | failure-marker-reconcile | all | `modules/failure-surfacing.nix` |
| D42 | tripwire-coredump, tripwire-user-unit-failure (all); tripwire-nas-reachability, tripwire-attic-cache-health (strix); tripwire-strix-reachability (client, #514) | all | `modules/tripwire.nix` |
| D43 | nix-gc (weekly), gc-root-reaper (daily) | all | `modules/gc-retention.nix`, `modules/gc-root-reaper.nix` |
| D44 | atticd GC every 12 h | NAS | `hosts/nas/attic.nix` |
| D45 | btrbk-nas (first Saturday 08:00), btrfs-scrub-mnt-nas (monthly) | NAS | `hosts/nas/snapshots.nix`, `hosts/nas/storage.nix` |
| D47 | docker-registry-garbage-collect (weekly) | NAS | `modules/ax-fleet/control.nix` |
| D48 | artifact-reaper (daily) | strix | `modules/caddy-artifacts.nix` |
| D49 | fstrim, logrotate, fwupd-refresh, systemd-tmpfiles-clean (system and user) | all | NixOS defaults |
| D50 | smartd (`-n standby,q`; a daemon, not a timer) | NAS | `hosts/nas/storage.nix` |

Besides these, the silent-hours releases are `paper-daemon-flush.timer` and the
06:05 entry of `speech-queue.timer` on the strix. Adding any other timer or
`OnCalendar` to this repository needs Tom.

**Closet and physical seat (Tom, 2026-10-08).** Strix (formerly coordinator)
is permanently headless in the closet, with the NAS, BE550 and Freebox. Both
closet computers use Ethernet. Strix is 10.42.0.2 on enp191s0; Wi-Fi is disabled
on reboot. NAS is the sole ordinary Tailscale node and advertises the closet
LAN; Strix has no Tailscale daemon. The worker is retired and must not return.
The Zenbook client is the physical seat, with Sway, Huion and Magic Trackpad.
Otto is rejected. Speech defaults to client; synthesis remains on Strix.
Preserve Herdr sessions: stage this network change for a deliberate reboot,
never activate it during an attached working session.

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
Strix at `http://strix:8731` via `modules/halogen.nix`: a pinned OCI image
run by podman, with the weights loaned from the NAS Library into
`/var/lib/local-models/halogen-qwen38-flash-next`. It is OpenAI-compatible
(`/v1/chat/completions` streaming and non-streaming with tool calls,
`/v1/responses`, `/v1/completions`, `/v1/models`, `GET /health` as the
liveness and discovery probe), carries the vision tower, so OCR and image
reading go through it too, and needs no authentication. The model id is
`halogen-qwen3.8-flash-next`; a request naming another id is not rejected.
A second Halogen engine, halogen-server with Qwen3.8-27B, is declared as
`services.halogen.alternates.qwen38-27b`: same port, same launch shape, never
resident together with Flash (the units conflict), started only by an
operator's `halogen-switch qwen38-27b` and put back with `halogen-switch
flash`. Flash is the everyday model; the 27B is the alternate.
**One compute host (Tom, 2026-10-08).** `modules/strix.nix` declares both
engines on Strix. Flash starts at boot and is the utility endpoint. The alternate
remains an operator switch. Immich ML also moved to Strix; its socket starts it
on demand, with a 15-minute idle shutdown. There is no worker host.
There is no `/v1/embeddings`, no reranking, no audio, no image generation, no
hot reload and no second resident model on a host. The token budget covers thinking: default
`max_tokens` 8192, cap 65536. Stable diffusion is outside this LLM route.

**The NPU path is decommissioned — permanently, 2026-08-29.** FastFlowLM (`flm`)
is no longer installed on any host, and the XDNA2 NPU is not an inference target
on Strix. Strix boots with `amd_iommu=off`, which is by
itself enough to make the old NPU path unbootable; this is a decommission, not a
pause. Do not add a `flm` invocation, an `flm serve` unit, or an NPU backend row
back.

**The `utility` slot forwards to halogen.** The stable ID `utility` resolves to
Strix's Halogen Flash server, and the request-scoped `utility-model`
wrapper — installed on the strix only — forwards a single
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
TTS inference runs on the strix GPU; the ASUS Zenbook (`client`) only
plays the returned audio. Speech weights follow NAS Library/explicit borrowing.
`modules/qwen-tts.nix` owns on-demand synthesis, separate from Halogen; it idles
out and has no boot target. Deterministic text chunks are stitched into one WAV.
The human is **Tom**; use his name naturally in assistant-written addresses,
without rewriting quoted documents or verbatim transcripts.
**Speech input is OUT (Tom, 2026-09-30):** the Alexa/openWakeWord wake listener
(`speech-wake`), Parakeet transcription, native Herdr hold-Space dictation and
the wake toggle were removed from every host, the Zenbook included. Do not
reintroduce a wake detector, a resident transcription service or a dictation
patch without Tom.

The strix's other model rows are task-specific. Qwen3-TTS 1.7B Base Q8
with the `qwen-k2so-midway-b` voice is the one TTS model (`modules/qwen-tts.nix`;
the voice has a second verified copy at
`/mnt/nas/documents/voice-references/qwen-k2so-midway-b/`, because it cannot be
re-downloaded). VibeVoice-ASR-Streaming-7B is the one diarization model, loaded
per run by `call-diarize` (Tom, 2026-09-16). The Qwen3 text embedder and the Mage
rows are NAS-Library artifacts an operator loans with `local-models-borrow` and
runs by hand; they have no declarative service, timer or proxy row.
Embeddings in particular have no server behind them until an operator starts
one.

Out, and not to be reintroduced: dual-node inference of any kind (the Thunderbolt and direct 5GbE rails are retired), the flashnext / flashnix / vLLM-fork projects (flashnext-fp8 and
qwen38-flash-next-fp8 included), DS4 / DeepSeek, GLM, every Gemma model
(supergemma included), Ornith, Muse Glimmer, IBM Granite, the GGUF
Qwen3.6-35B-A3B, Qwen3.6-27B and Qwen3.8-27B (the `.hgn` `halogen-qwen38-27b`
stays), Gemma 4 31B, every Qwen3-VL row (instruct, projectors and the VL
embedder), every FARA 1.5 model (4B, 9B, 27B) together with its browser agent,
the FLM NPU models, Flash-Next in other formats (UD-IQ3_XXS, the ciru IU4
reference), qwen3-coder-next, the sherpa-onnx keyword-spotting research model,
every VibeVoice except `vibevoice-asr-streaming-7b-bf16`, every Qwen TTS variant
except the production Base Q8 + tokenizer + K-2SO voice (VoiceDesign,
CustomVoice, the K-2SO CustomVoice experiments, khimaros, 1.7B BF16, 0.6B), and
the uncensored candidates (Tom, 2026-09-11 and 2026-09-16). A new engine is a
new server module beside `modules/halogen.nix`, or it does not serve.

The weight plane lives outside Nix. `hosts/nas/models.nix`'s `library-fetch`
is the only thing that talks to Hugging Face; it fills the canonical NAS
Library and never deletes. A host's wanted set is declared in Nix and rendered
to `/etc/local-models/wanted.json`, but activation moves no bytes:
`sudo local-models-borrow --dry-run|--yes` copies and verifies wanted
artifacts from the Library into `/var/lib/local-models`, and
`sudo local-models-prune --dry-run|--yes` is the only thing that deletes a
loaned copy, and only when the set it computed has not changed underneath it.
`docs/nas/model-archive.md` is the retire/restore runbook; retired Library
bytes are listed in `/mnt/nas/models/weights/RETIRED-<date>.tsv`.

**Shared browser desktop (2026-09-12).** Strix keeps `myDisplay.enable =
false`: no physical Niri/greetd session. `modules/browser-desktop.nix` supplies a
separate on-demand headless Sway seat with WayVNC on loopback and stock noVNC
served by Caddy at `https://browser.internal` on BE550. The lightweight launcher
starts at boot; Sway, WayVNC and Chrome do not. Sessions stop five minutes
after the last viewer disconnects. This exception is Strix-only; NAS has no compositor/VNC. The sidebar opens ordinary installed
Chrome profiles and unlocks the keyring. The FARA agent loop (`fara-browser`,
its model unit and skill) was removed with FARA on 2026-09-16 (Tom).
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
strix Caddy and a CPU-only service. Preserve `/var/lib/handwriting-annotation`
and its append-only writer/model-review history across updates. Model-assisted
resolutions are not writer labels. Huion sources arrive in `~/Paper/inbox`;
`~/Paper/intake` is the printing route. Use the existing Halogen Flash for serial
OCR with thinking explicitly off. `docs/handwriting-intake.md` records the
recipe, correction-evidence rules and real-Huion commissioning boundary. Do not
reseed live review state or treat stable legacy capture files as proof of device
page completeness.

**Speech integration (2026-09-14, input half removed 2026-09-30).** There is
no Gemma/router layer in the daily flow. Gemma and the non-streaming VibeVoice
ASR are retired (2026-09-16). No service startup downloads models. Use the NAS
manifests and explicit `local-models-borrow` transactions documented in
`docs/speech-operations.md`.

The shared `/speak` skill publishes visible Markdown files in `~/Speech/intake`;
the daemon synthesizes and plays through a seat during 06:00–24:00, matching
paper working hours, with a 06:05 release for anything held overnight.
Publishing a queue file is not evidence it was heard: consult playback receipts.

Keep the Herdr server's `X-SwitchMethod=keep-old` protection: deployment must
not kill live PTYs. Existing client processes need a new projector launch to
load a changed binary.

The original montage, accepted midway B enrollment and evaluation outputs are
preserved on NAS; superseded speech model weights were deleted on 2026-09-16
(receipt in `/mnt/nas/models/weights/RETIRED-2026-09-16.tsv`). See
`docs/mykonos-overnight-integration.md` for the rollout/acceptance record, rather
than inferring activation from these declarations.

**Speech cleanup (2026-09-15).** Use functional speech names, never the idea’s
location as a product/service name. Hands-free follow-on conversation routing is
explicitly dropped. Keep supported implementation and tests in dotfiles; delete
superseded experimental code rather than archiving it on NAS. Keep listening
evidence and canonical model weights separately.
