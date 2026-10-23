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
when typed from `~`; never start a seat in the home directory. `~/today` carries
no brief file (its stale CLAUDE.md was moved out on 2026-10-13, Tom: cc and cc2
keep starting there), and there is no third seat (Tom, 2026-09-22: "no more cc3"). Logins are hand
`/login`s, never a delivered secret (the old claude-credentials seed was removed
this day). `seats` reads its peer cache from `~/.local/state/tally-rewrite/meters`
(the directory name outlives Tally, which was removed on 2026-09-30).

**Model catalog (Tom, 2026-10-10).** Model ids for the factory are runtime data, not nix: they live in `~/.config/substrate/models.toml`, seeded by the substrate-puller unit when the file is absent and never rewritten by nix (`services.substrate.puller.modelsFile`, named in runtimes.toml as `models_file`; the runners re-read it on every call, so a model edit needs no rebuild). Tom: "i dnt think it s a g ood idea to have things like that tied to nixos dotfiles". The openrouter-free lane is parked (no entry in the catalog, so substrate refuses that runtime and route policies fall through) until OpenRouter releases a new stealth model; no harness on the fleet routes to the OpenRouter key since pi was removed; seats reads it for the credit row, and a dsh route or retiring the key is a follow-up. The puller PATH carries Node 24 and pnpm 11.17.0 (`pkgs.pnpm_11_17`, the stack v1 pin) so a spec-task gate runs `node` and `pnpm` bare.

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
| D48 | artifact-reaper (daily) | strix | `modules/caddy-artifacts.nix` |
| D49 | fstrim, logrotate, fwupd-refresh, systemd-tmpfiles-clean (system and user) | all | NixOS defaults |
| D50 | smartd (`-n standby,q`; a daemon, not a timer) | NAS | `hosts/nas/storage.nix` |

Besides these, the silent-hours releases are `paper-daemon-flush.timer` and the
06:05 entry of `speech-queue.timer` on the strix. Adding any other timer or
`OnCalendar` to this repository needs Tom.

**Nightly update check (#550, Tom 2026-10-14).** Tom: "nightly, i want to be
chekcing codex and cc and other programs for their latest version and
ingesting it, potentially also with the new features that they entail". The
clock is a substrate floor routine (substrate T-7), never a timer here. This
repo holds the logic: `update-check` (home/dot_local/bin) reads
`lib/update-watch.json`, and for each input whose upstream moved a program we
use, rebuilds the rolling branch `update/<input>` from main, runs the gate and
opens or refreshes one PR. The PR is a draft when the gate fails. The check
skips the bump when no watched program changed version, and closes the PR
once main carries the input. Fish, kitty and Wrangler ride the existing nixpkgs-fresh leaf overlay;
new stable kernel major.minor series are issue watches. The Projects
floor routine uses `update-check --if-idle --background --json`: soft hourly opportunities,
load/Nix/Herdr admission checks and one completed attempt per Paris night.
Every defer and failure is recorded. The detached worker survives the Floor
turn limit, inherits its lock and writes a durable job result; a launch receipt
is not a successful check. No local timer is installed. Digests are
opt-in and comment-only; the routine makes no adoption commits. Earlier
review commits without `Update-Check: bump` survive refreshes, or a conflict
aborts before the remote changes. Nothing merges, switches or restarts without
Tom. Adding a program is an entry in the watch file.
Imported release notes must stay in collision-safe literal text fences, with
only their release-page links outside. Contributor mentions and upstream
issue/PR references must never become active GitHub Markdown in generated PR
bodies or digest comments (2026-10-22 notification incident). Truncate source
text before fencing it, never the rendered wrapper.

**Closet and physical seat (Tom, 2026-10-08).** Strix (formerly coordinator)
is permanently headless in the closet, with the NAS, BE550 and Freebox. Both
closet computers use Ethernet. Strix is 10.42.0.2 on enp191s0; Wi-Fi is disabled
on reboot. NAS advertises the closet LAN through ordinary Tailscale. Strix
retains its own Tailscale identity as an independent fallback, per Tom's final
decision; Zenbook is also enrolled. Use ordinary OpenSSH on both paths.
The worker is retired and must not return.
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

**Gufo replaces Halogen (Tom, 2026-10-13).** Tom: "i said let  move to
gufo!! not halogen!!!!" and "use that as the full collection of modles that we
use". The engine is `gufo` from github:gufo-org/gufo (flake input `gufo`,
`modules/gufo.nix`): one native gfx1151 binary, one systemd unit per model, no
container. Its model collection is the fleet's model set, catalogued in
`lib/gufo-models.json` at the revisions Gufo's docs pin:
- Qwen3.8 Flash-Next (UD-Q4_K_XL GGUF with the MTP predictor and the vision
  projector): the resident text model, served as `qwen3.8-flash-next` on
  `http://strix:8731` (`gufo-llm.service`);
- Qwen3.8-27B (UD-Q4_K_XL with the DFlash2 draft) and DeepSeek V4 Flash (with
  DSpark): alternates on the same port, started only by `gufo-switch <name>`;
- Qwen3-TTS 12Hz 1.7B Base, Qwen3-ASR 1.7B and Qwen-Image-2.1: on-demand
  loopback units with no boot target (ASR runs per job, never resident);
- MiniMax H3 FL2VA: held by `source.gate` until Tom accepts its licence himself.
Gufo answers 404 to a request naming any other model id, so callers send the
exact served id. It has no `/v1/embeddings` (501), no reranking and no
diarization.

**Until the cutover, Halogen still serves.** Halogen Flash
(`modules/halogen.nix`: Qwen3.8-Flash-Next in Peonist's `.hgn` format, model id
`halogen-qwen3.8-flash-next`, alternate `halogen-switch qwen38-27b`) stays the
live endpoint at `strix:8731` until `services.gufo.enable` is switched on with
`services.halogen.autoStart = false`. The Gufo and Halogen units conflict, so
they never hold the GPU together. Do no Halogen-specific work (Tom,
2026-10-13); after the cutover the `.hgn` rows and `modules/halogen.nix` are
retired. Immich ML also runs on Strix; its socket starts it on demand, with a
15-minute idle shutdown. There is no worker host.

**The NPU path is decommissioned — permanently, 2026-08-29.** FastFlowLM (`flm`)
is no longer installed on any host, and the XDNA2 NPU is not an inference target
on Strix. Strix boots with `amd_iommu=off`, which is by
itself enough to make the old NPU path unbootable; this is a decommission, not a
pause. Do not add a `flm` invocation, an `flm serve` unit, or an NPU backend row
back.

**The `utility` slot forwards to the local text model.** The stable ID
`utility` resolves to Strix's resident text model (Halogen Flash until the
Gufo cutover, then Gufo's Flash-Next), and the request-scoped `utility-model`
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
per run by `call-diarize` (Tom, 2026-09-16); Gufo has no diarization, so it
stays. There is no embedder row in the catalog and no embeddings server.

Out, and not to be reintroduced: dual-node inference of any kind (the Thunderbolt and direct 5GbE rails are retired), the flashnext / flashnix / vLLM-fork projects (flashnext-fp8 and
qwen38-flash-next-fp8 included), GLM, every Gemma model
(supergemma included), Ornith, Muse Glimmer, IBM Granite, the GGUF
Qwen3.6-35B-A3B and Qwen3.6-27B, Gemma 4 31B, every Qwen3-VL row (instruct, projectors and the VL
embedder), every FARA 1.5 model (4B, 9B, 27B) together with its browser agent,
the FLM NPU models, Flash-Next in formats other than Gufo's UD-Q4_K_XL
(UD-IQ3_XXS, the ciru IU4 reference), qwen3-coder-next, the sherpa-onnx keyword-spotting research model,
every VibeVoice except `vibevoice-asr-streaming-7b-bf16`, every Qwen TTS variant
except the production Base Q8 + tokenizer + K-2SO voice and Gufo's 1.7B BF16
Base (VoiceDesign, CustomVoice, the K-2SO CustomVoice experiments, khimaros,
0.6B), and
the uncensored candidates (Tom, 2026-09-11 and 2026-09-16; Gufo's collection,
2026-10-13, overrides the lines it conflicted with: DeepSeek, the GGUF
Qwen3.8-27B, Flash-Next as GGUF, the BF16 TTS Base). A new engine is a new
server module beside `modules/gufo.nix`, or it does not serve.

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
false`: no physical Sway/greetd session. `modules/browser-desktop.nix` supplies a
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
`%h/.local/bin/<program>` is missing from that checkout. The client is the
exception (2026-10-11): `rawDotfiles.inStore` copies the same files into the
Nix store, so it has no checkout, no guard and no bootstrap clone, and a
`deploy` from the strix is its only update path. Do not clone the repo there.


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
