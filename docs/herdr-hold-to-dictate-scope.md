# Herdr hold-to-dictate: proposed unification

Tom's intended scope: terminal-only dictation into arbitrary Herdr panes,
including coding agents and Neovim, using the Zenbook USB microphone and
coordinator Parakeet. This is insertion into the existing application, distinct
from Alexa opening a new Claude speech session. Qwen output stays independent.

## Latest ruling

Tom explicitly retired herdr-kitten. Do not build, extend, deploy or depend on
`hk` voice hooks. The earlier suggestion to reuse them is withdrawn. This does
not retire Herdr itself or the existing microphone/coordinator transport.

## Existing building blocks verified locally

- `home/dictate-hold.py` already implements client Mod+Space and streams raw
  PCM to coordinator `voxtype-relay`. It uses the default microphone and injects
  through the original projector, whose internal pane focus can change while
  transcription is pending. These are the gaps to fix, not proof of a finished
  arbitrary-pane solution.
- Herdr itself exposes the pane input API. Use that native API and its
  terminal-mode-aware paste handling directly; no herdr-kitten wrapper.
- Herdr's client already requests key event types and handles press/repeat/release.
  Its existing command bindings are not a timed bare-Space dictation feature.
- Neovim's local configuration sets Space as mapleader. Intercepting bare Space
  is therefore a deliberate interaction change, not a harmless key remapping.

## Shared transport contract

One recording session owns the microphone. Snapshot the client window, Herdr
pane/terminal and current occupant before capture. Begin indication → exact USB
mic capture → bounded PCM streaming → coordinator resident Parakeet → final
transcript → literal input to that same still-valid destination. Never press
Enter, launch Claude, select an LLM router or rewrite the transcript for this
mode. No fallback to an arbitrary focused desktop application. Cancel on Escape,
call recording, capture loss, transport failure or invalidated destination;
focus changes should default to cancellation rather than surprising insertion.

Push-to-talk ends on key release; Alexa ends on VAD. They share transport,
model service, cancellation and device policy. Holding a key must inhibit Alexa
so one utterance cannot take both paths. Media/call policy must be shared too.

The current resident Parakeet relay is a measured working backend; a direct
persistent Parakeet endpoint can replace it behind this contract if justified.
Do not reinstate fresh per-utterance Voxtype CLI processes: their teardown failed
in four of fifteen saved-file tests. The old asr-rs archive is a transport
reference, not a proven current GPU implementation.

## Gesture decision

Bare Space: buffer the press briefly; a tap sends an ordinary Space on release,
and another key before the threshold flushes Space first to preserve typing and
leader sequences. A hold beyond a provisional300ms threshold consumes repeats,
starts dictation and sends no Space. Release finalizes. This alters long Space
holds and can trigger while someone pauses with a Neovim leader held down.
Implement this in Herdr’s native client input handling if selected; do not globally grab and reinject all
keyboard events merely to avoid that implementation work.

Mod+Space: existing compositor trigger avoids delaying normal typing, while
still restricting capture to Herdr. It can reuse the current release detector.
Tom was asked which gesture he wants; no new keybinding was installed by this
scoping pass. Existing Alexa operation was not disabled.

## Acceptance before activation

Verify short Space taps, rapid typing and Neovim leader sequences; release and
lost-release timeout; repeat suppression; Escape/focus/pane-occupant changes;
USB unplug; call and playback inhibition; concurrent Alexa attempt; empty
transcript; multiline literal insertion without submit; and remote reconnect.
Measure key release to final insertion using the same recordings as the ASR
comparison. Keep microphone readiness, transport, transcription and delivery
receipts separate so slowness is attributable.
