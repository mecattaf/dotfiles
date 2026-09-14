# Coordinator intake: first local measurements

These are preliminary results on saved audio, not a final architecture selection.
**Diagnostic result: the 12B transcription problem was fixed on these English
fixtures by an explicitly English-to-English ASR instruction.** Both ordinary
passages, the actor excerpt and routing request then contained only the correct
spoken words (with K2SO typography differences); silence returned empty. This is
prompt sensitivity in the tested setup, not evidence of an inherent inability to
process audio. Multilingual behavior and the separate dense-context failure remain
unresolved.

## Corrected 12B transcription

The short user-message prompt alone did not fix unwanted translations. Explicitly
asking for English into English, transcription only and no newlines did. The
completed response times were 2.56s for the short passage (warm repeat), 2.08s
for the actor, 4.76s for the technical passage (warm repeat), 2.29s for the
routing-request transcription and 0.41s for silence. E4B remains faster on these
clips, but the broken initial 12B output must not be used as its final ASR result.
No model weights or runtime were changed for this correction. The wording also
specifies digit formatting; language anchoring was not isolated in a one-variable
ablation. No postprocessing hid extra output.

## Initial controlled comparison (before 12B prompt correction)

All model inference ran on coordinator. Gemma weights and matching projectors
were acquired through NAS Library and explicitly borrowed. The pinned ROCm
llama-server is version 9925 (ed8c261), full GPU offload requested, thinking off,
temperature 0, seed 42, no MTP, context 32768. Qwen was stopped during these tests.
The same five mono 16 kHz WAVs cover ordinary synthetic speech, technical synthetic
speech, a human actor excerpt, silence, and a synthetic dotfiles routing request.
The two ordinary passages and actor excerpt each have two Gemma repetitions.

| Probe | Parakeet via existing relay | Gemma E4B-it Q8 | Gemma 12B-it Q8 |
|---|---|---|---|
| Ordinary passages | Correct words | Correct words | Correct English followed by unsolicited translation |
| Actor excerpt | K2SO formatting difference | K2SO formatting difference | Additional translation |
| Silence | Empty | Empty | Requested an audio upload |
| Dotfiles transcription | Misheard dotfiles as “the.files” | Correct, 0.89s | Correct wording duplicated, 3.87s |
| Short audio routing | Not a router | Correct transcript and destination, 1.58s | Correct transcript and destination, 3.25s |
| Dense audio routing | Not tested | Correct, 20.76s | Incorrect transcript and destination, 44.59s |

Gemma times measure receipt of a complete WAV through complete HTTP response.
Parakeet's existing relay replays audio into a virtual microphone at real time;
its measured wall time minus audio duration is about 0.54–1.13s, including relay
and capture overhead, not isolated inference. These numbers are not equivalent
end-to-end metrics. No laptop recording, VAD end detection, SSH transport or
agent response is included in the Gemma times.

The dense probe has approximately 23,350 actual input tokens of a constructed
inactive catalog plus a routing instruction. It is not the Reddit author's real
system prompt or a full agent history, and does not establish a general failure
threshold. Both models returned fenced JSON, accepted after stripping fences;
strict schema adherence was not demonstrated.

12B reached 12.13 GiB process RSS and 13.58 GiB system AMD GTT; E4B reached
7.81 GiB RSS and 6.96 GiB GTT. These shared-memory measures overlap and must not
be added. The 16 GiB available-memory/64 GiB GTT guard did not fire. This does not
constitute a kernel-log audit or proof that all GPU allocation issues are fixed.

## Interpretation and follow-up

E4B is the stronger Gemma candidate in this small suite. Parakeet remains the
established transcription baseline. Neither should be crowned from five clips;
Tom's actual voice, French/code-switching, names and background noise remain to
be evaluated. The actor excerpt's WER includes orthographic K-2SO/K2SO differences.

Keep a literal transcript and an explicitly selected agent session as the normal
path. A small routing call is optional when the destination is unbound. Do not
load all agent instructions/tools into an audio frontend by default. No session
adapter or automatic agent dispatch has been activated.

A separate short user-message transcription prompt tests 12B output sensitivity.
It changes both wording and placement, so cannot isolate either effect alone.
An upstream research pass is investigating task markers, projector compatibility,
templates and known runtime defects before attributing failures to model quality.

Google documents a 30-second audio limit. Longer capture needs a separate tested
segmentation policy; large text context does not prove longer audio support.
[Official audio guide](https://ai.google.dev/gemma/docs/capabilities/audio).

## Evidence and reproduction

Runner and invocation instructions: [tools/speech-intake](../tools/speech-intake/README.md).
Raw results and fixtures are under `/home/tom/tts-intake-gemma-20260914/`:
`runs/{12b,e4b,12b-user-asr}/`, `runs/parakeet/summary.json`, and
`fixtures/manifest.json`. Each Gemma case preserves raw text, stream events,
request latency, audio/prompt hashes and token usage. Model manifests pin hashes.
No model cleanup, merge, or fleet activation was performed.

The accepted Qwen Base single voice remains separate and unchanged. `/speak` has
a draft Markdown-drop skill; its queue daemon is not yet implemented. Alexa CPU
wake/nudge and call-record inhibition are prepared in the worktree but not enabled.
