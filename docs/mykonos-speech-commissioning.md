# Speech pipeline commissioning — 14 September 2026

The temporary runtime is active; the main dotfiles checkout has not been merged
or rebuilt. The final Qwen voice has not yet been archived and no models were
removed. All speech/transcription inference runs on coordinator; only wake/VAD,
USB microphone capture, transport and playback run on client.

## Current path

Alexa on the iContact USB microphone → original listening cue → stream 16 kHz
PCM over SSH while Tom speaks → resident Voxtype/Parakeet on coordinator →
0.8-second client VAD tail → complete transcript → a new named Herdr workspace
and Claude Opus session → Markdown file drop → Qwen → one stitched WAV → client.
Every accepted nonempty transcript creates a NEW session. Follow-on voice
addressing is not implemented. The same session accepts ordinary keyboard
follow-ups with speech still on. `Respond` is not a selected wake word; Alexa
was retained after checking openWakeWord's pretrained list.

The launcher passes the usual `cc` permission setting, `--model opus`, a unique
session UUID and a compact appended system prompt describing the speech setup.
Transcript input is passed literally, not interpolated into shell code. Herdr's
agent API addresses the returned pane, never the currently focused terminal.
The client opens a dedicated kitty window attaching to that pane's persistent
Herdr terminal. No Niri brightness or display-power action is used. This direct
terminal attachment is intentionally simpler than the full Herdr sidebar UI.

The `/speak` source is in `home/dot_claude/skills/speak/SKILL.md`. New speech
sessions already receive its file-drop contract in their appended prompt; the
global Home Manager Claude skill tree is not switched yet. The daemon watches
`~/Speech/intake`, holds work during 00:00–06:00 local time, renders Markdown
without an LLM and synthesizes using the accepted single K2SO reference. Files
and playback receipts stay under `~/Speech`. Failed/uncertain playback is never
silently replayed. `/speak off` stops new drops, not already queued audio.

## Playback and calls

The event-driven PipeWire monitor inhibits waking during running output streams,
including arbitrary media players, plus a 0.5-second tail. It excludes only the
specifically tagged listening cue. No model or microphone inference is needed
for this monitor. Its failure inhibits waking. Paused players should cease to
inhibit when their stream stops; an app retaining a running silent stream may
keep listening inhibited. Pause/stop the player before addressing Alexa. This
is not acoustic echo cancellation or a guarantee against audio from another
physical device.

Qwen playback also takes an explicit lock, publishes an epoch and waits for the
listener's acknowledgement before playing. Call-record entry/exit has its own
epoch handshake and clears queued audio. Manual call mode remains available.
The prototype's whole-utterance replay delay was removed: audio now travels to
the existing virtual source while it is captured. Generic Mod+Space dictation
still uses its existing default-source policy; only this Alexa flow is pinned
to the USB iContact microphone.

## Evidence and limitations

The same five saved source WAVs were evaluated through Gemma and resident
Parakeet. Parakeet's stream-end-to-transcript times were 0.499, 0.552, 0.781,
0.494 (silence, empty) and 0.547 seconds. The routing WAV took 0.888 seconds in
resident E4B and 2.29 seconds in corrected 12B. Parakeet includes the virtual
source's 200ms tail; Gemma starts with a complete WAV. These exclude client VAD,
SSH return and live wake latency. They compare useful post-input behavior, not
identical model internals or a measured complete Alexa-to-response round trip.
Parakeet rendered dotfiles as “Dot Files” in the live relay, and as “.files” in
some direct file runs. E4B/12B preserved that name. Keep raw transcript evidence.

Fresh `voxtype transcribe` runs produced four teardown SIGABRT failures out of
fifteen despite first emitting text. Do not use that CLI once per utterance as
a fallback. The resident relay completed all five tests. A direct persistent
Parakeet server remains authorized if Voxtype transport proves unreliable; it
has not been adopted or AMD-validated in this pass.

Two new Claude-session checks generated Markdown, Qwen WAVs and successful
client playback receipts; Tom confirmed audible output. The corrected launcher
created session `fa9afa36-6f26-4949-9de7-07b4d47f4a9f`, pane `w55:p1`, and left it
open. The earlier session `bee6a004-4ca3-4f29-9200-ff6084214019`, pane `w54:p1`,
was recovered after Herdr rejected a multiline system argument; the launcher
now collapses that prompt to one line before passing it as an argument.
These checks fed text directly: they are NOT proof of the full acoustic chain.

The live listener armed on the exact USB microphone and logged an Alexa at
22:35:30. A subsequent silent generic-media test at 22:35:34 inhibited and
canceled that capture, then listening rearmed at 22:35:40. The test therefore
proved media suppression, not successful delivery of that user's utterance.
Tom subsequently spoke “Testing this again, what is the sum of pi and thirty-four?”
at 22:35:57. The endpoint was 22:36:03, transcription finished 0.558s later,
and session 7fb7f4b9-c3cd-4c12-b00f-94b8b2613e5d (w56:p1) was submitted at
22:36:08. Claude answered correctly. Its Markdown was mistakenly left as a
hidden .md file, so the daemon did not consume it. The commissioning agent
published that completed file manually at 22:36:57; Qwen playback completed at
22:37:05 and Tom acknowledged hearing it. Thus acoustic input and final output
are demonstrated, but this turn required a manual queue-publication repair.
The system prompt now explicitly removes BOTH the leading dot and .tmp suffix,
with concrete before/after paths; the open session received that correction.
New session launches use the corrected build. Repeat fully automatic live
acceptance remains the next check, not something this repaired turn proves.

## Temporary runtime and rollback

Client user unit `mykonos-wake.service` runs the pinned worktree build with
`--live --dispatch`; it was started, not enabled at boot. Stop it with:

```sh
ssh client systemctl --user stop mykonos-wake.service
```

Coordinator user units `mykonos-speech-queue.path` and `.timer` are started, not
enabled at boot. Their service points at the commissioning store build. Stop
both triggers to pause automatic output; stop the service too to interrupt an
active job (which will subsequently require review).

The client call-record script and coordinator voxtype-relay were updated as
runtime copies; originals are preserved on each respective host in
`~/.local/state/mykonos-commissioning/{call-record,voxtype-relay}.before`.
Do not restore the old call hook while the listener is running. The coordinator
`~/.local/bin/mykonos-session` wrapper points at the new store build. Final
merge/activation should replace these temporary overrides with declarative
packages/units and retain the accepted voice enrollment.

The requested two-page assessment printed successfully; receipt:
`~/Paper/printed/mykonos-intake-parakeet-gemma-20260914-223135/receipt.json`,
`pages=2`, `impressions_completed=2`, printer job303.

## Fixed launch prompt verification — 22:38

The filename correction is now part of the package's immutable system.md,
passed through --append-system-prompt at Claude startup. The launcher no longer
accepts a --system-file override and records the exact normalized prompt and
its SHA256 in each session receipt. The live launcher points at
/nix/store/pnn9siiy8v401z651qj1dix0mwm7w02j-mykonos-speech-0.1.0.

Fresh session eb809d37-a5c0-440d-8801-aabf18359b49 received only the user question
“What is two plus three? Answer in one short sentence.” No chat-side correction
or speech reminder was sent. It published a visible turn-001.md automatically;
the queue generated and played it successfully at22:38:50. Receipt:
~/Speech/spoken/eb809d37-a5c0-440d-8801-aabf18359b49-turn-001/receipt.json.
This verifies automatic publication from the fixed system prompt in a fresh
session; it used direct text for this isolated check.
