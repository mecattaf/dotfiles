# Overnight integration — 14 September 2026

Tom authorized completing the voice integration, creating and merging a dotfiles
PR, fleet activation, and removing the completed worktree. This record separates
that target from observed completion. Do not remove the worktree until its
commits and evidence are preserved and the fleet validation passes.

## Final scope

- Single accepted Qwen Base Q8 / K2SO midway B voice; deterministic chunks and
  final stitched WAV. Preserve liked original baseline and research as history.
- Markdown-drop `/speak` for Claude and Codex, same waking hours as `/print`.
- Client Alexa CPU detection, original nudge, exact iContact USB microphone;
  calls and media playback inhibit capture. No brightness actions or overlays.
- Coordinator Parakeet directly, persistent GPU worker, NAS-backed pinned model.
  Replace Voxtype only after saved-audio, lifecycle and client transport checks.
- Bare Space tap remains text; hold dictates in Herdr. Native Herdr/kitty protocols
  are authorized; no dedicated kitten. Original pane delivery, no Enter.
- All STT/TTS/LLM inference on coordinator. Client has audio and wake components.
- Gemma, VibeVoice and CustomVoice experiments stay archived, not daily services.

## Audit findings

Read current commissioning records, accepted voice provenance, intake comparison,
Mykonos annotations and auxiliary Claude session
552535b2-f969-4c2a-82fa-edb795fc7310. Earlier annotation preferences are superseded
by Tom's final choices above. Voxtype's four standalone teardown aborts are real
failures; suppressing coredumps does not fix them. The old asr-rs archive is a
transport reference, not a validated current AMD runtime.

Temporary runtime units still need declarative replacement. Main checkout has
unrelated README edits, a commissioning relay copy and session wrapper; preserve
unrelated edits and reconcile the voice copies explicitly before activation.
Main is 3a300271 at audit start, same base as work/qwen-tts-zenbook.

## Implementation checkpoints

- Direct engine candidate: parakeet-rs 0.3.7, pinned Cargo lock, MIGraphX provider
  registration must fail rather than silently falling back. Normal process
  teardown remains enabled for lifecycle validation.
- Existing Parakeet model files are being verified against upstream revision
  8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce, imported into NAS Library, then explicitly
  borrowed to coordinator. No bootstrap downloads belong in the replacement unit.

No PR, merge, fleet switch, Voxtype removal or worktree removal has occurred yet.

Direct Parakeet 0.3.7 completed 15 saved-audio requests across three independent
loads, all three normal teardowns exit 0. Warm short/actor/technical/route inference
approximately .33/.21/.42/.17 seconds; silence empty. The domain word dotfiles
remains misrecognized as .files, matching the previous direct-file behavior.
Framed socket tests verify busy rejection, disconnect cancellation, subsequent
reacquisition, and real GPU transcription. Startup warmup remains separate.

Parakeet weights and accepted K2SO voice/provenance were hash-verified on NAS then
explicitly borrowed back. Neither operation pruned anything. Local derived voice
metadata now distinguishes imported artifacts from downloadable checkpoints.

Hold-Space is being implemented as a client-only patch against the existing
pinned Herdr revision, with its native pane-targeted input protocol. No upstream
PR or server protocol change. Deployment remains pending its tests. A normal tap
or Space followed by another key flushes a literal Space; holding 300ms invokes
the thin capture helper. Calls, playback, focus changes and Escape cancel.

Durability work now includes home/mykonos.nix (coordinator Parakeet and client
wake units), a NAS-restorable fallback voice profile, and catalog entries for
openWakeWord frontend/classifier and the parked Gemma audio artifacts. Existing
Voxtype remains declared until hold-to-dictate acceptance. The compiled native
Herdr adapter and thin helper have not been installed into daily projectors yet.

Checkpoint 23:23 CEST:
- Native Herdr production build and five focused input tests pass. The real kitty
  trial inserted a fake result without Enter. Longer integrated runs are still
  under investigation: a key event cancels the helper shortly after startup.
  Do not retire Voxtype until that acceptance gate is resolved.
- Direct helper + paced nine-second PCM fixture + SSH + resident GPU Parakeet
  returns the complete request. An exclusive-lock probe race between the wake
  observer and dictation observer caused false `qwen-playback` inhibition. Both
  observers now use shared locks; actual playback remains exclusive. Regression
  test passes (11 wake tests total).
- Low-volume acoustic loopback did not produce a usable transcript before that
  race was identified. Client speaker mute and 0.70 volume were restored.
- Six call-record acknowledgement tests pass with the actual script fixture.
- NAS research archive has 6,337 files (959,931,124 bytes), verified SHA256
  c8d433aeaa782c06e6177f710cd8232d293578f2a41e3f10acdc6570091d305b.
  Original montage MP3 is separately archived and hash-verified beside it.
- New `speech-operations.md` documents explicit client wake-weight restore
  via canonical NAS staging, runtime boundaries and historical research status.
- The live temporary client wake service now uses the direct Parakeet relay and
  shared-lock fix (`jlh478gdndcrh72bs493ij158cxqs3ix-mykonos-wake-0.1.0`). Its prior
  unit is backed up in `.local/state/mykonos-commissioning`. Client call-record
  matches the new capture-lock acknowledgement hook.
- Temporary coordinator `~/.local/bin/parakeet-relay` points at the trial socket;
  it must be removed when the packaged relay and declared unit take over. As
  `.local/bin` is a raw symlink, this file is an untracked commissioning file in
  main, alongside the previous mykonos-session wrapper.
- Unrelated main README edits and worker untracked quickshell files are preserved.
  NAS has no `~/mecattaf/dotfiles` checkout. No PR/merge/activation/Voxtype removal
  or worktree removal has occurred.

Checkpoint 23:28 CEST:
- Native integrated hold/release acceptance now passes in a real kitty window
  targeting new pane `w5A:p1`. The paced fixture travels through the actual thin
  helper, SSH framing and resident MIGraphX engine, then is pasted without Enter.
  This is repeatable digital input, not a claim of fresh human-microphone accuracy.
- The remaining cancellation was a real kitty media-mute event (CSI 57440),
  observed on the client as the cue started. Media/modifier events no longer
  cancel dictation; editing keys, Escape and focus changes still do. Seven native
  tests pass. No key-content tracing is enabled or retained in the final patch.
- Alexa-created windows now use the native client with a client-scoped initial
  pane target, so they gain the same hold-Space and clipboard support. They no
  longer use an SSH-only terminal attachment.
- Voxtype, its flake input, virtual mic configuration and old global evdev
  dictation bindings are removed in the branch. Live old Voxtype is still present
  until fleet activation. `nix flake lock` removed only its now-unused graph.
- Updated home-profile, deadnix and speech topology checks pass. All four final
  system closures are building. No merge or switch yet.
- All 28 speech-investigation artifact sets referenced by manifests exist on NAS;
  `mykonos-nas-inventory.json` records the presence check. This is not an additional
  full rehash of every historical model; canonical import receipts remain the
  hash evidence. Recent kernel log has no BO_VR/GPU fault/reset errors during the
  direct Parakeet work.


Rollout checkpoint 23:39 CEST:
- All four hosts successfully switched to clean source revision 49053f93. Main,
  client and worker raw checkouts were fast-forwarded first. Coordinator README
  edits and worker untracked quickshell files remain untouched.
- Coordinator Herdr server PID 1716 survived. Parakeet is enabled and running
  with MIGraphX; the speech queue path/timer are enabled. Client wake is enabled,
  armed on the exact USB microphone, and delivered by Home Manager. Temporary
  units/wrappers are backed up and removed. Voxtype is inactive/uninstalled; its
  old virtual mic is gone after restarting the idle coordinator audio services.
- Deployed Claude session 0a2adc9b-8f2f-44a0-8214-e5d7ec677982 used the fixed
  system-prompt hash 5eada394ff4827b871c5b134973dbf2f91bd40e694b29915b3c66e60434ff1a3.
  It automatically published a visible Markdown job; playback receipt reports
  success at 23:35:57 (12.82s queue work). This confirms delivery, not that Tom
  heard a muted speaker. His mute/volume settings were preserved.
- Runtime call-mode inhibition acknowledged microphone release. The real kitty
  tap-Space and Escape tests passed. The end-to-end digital fixture passed before
  activation; fresh acoustic accuracy is not inferred from it.
- Post-switch testing found and fixed the normal-kitty launcher syntax: environment
  is passed through `env`, not the remote-control-only `--env` option. The corrected
  packaged launcher opened a native window on w5B:p1 with hold-Space enabled.
  This small follow-up must be included in the final merged revision and rollout.
- Two-page Parakeet/Gemma brief was already printed successfully at 22:33:21,
  printer job 303 / CUPS Brother_HL_L2445DW-312, two impressions. No duplicate print.
- PR #387 contains the integration. The final merged-revision verification and
  safe worktree retirement follow this checkpoint; authoritative final receipt is
  stored beside the NAS research archive so recording it does not require another
  configuration revision solely to change a deployment timestamp.
