---
target_pages: 2
---
# Mykonos intake: Parakeet or Gemma?

14 September 2026 · Decision brief for Tom

**Recommendation: integrate resident Parakeet first; keep Gemma E4B-it and 12B-it as reproducible alternatives.** The job is accurate transcription followed by Claude Opus. A routing model adds no useful decision when the destination is always Claude. The latest saved-audio measurements favor Parakeet, with important implementation limits below.

## The requested flow

The Zenbook detects the wake phrase through its USB webcam microphone, nudges when capture is ready, and captures Tom’s command. Coordinator inference produces a literal transcript. A deterministic adapter opens a new `cc` Claude Opus session in herdr, supplies the transcript with a short explanation of the speech setup, and enables `/speak`. The terminal stays open for subsequent typed interaction. Niri brightness is untouched.

Claude authors the answer; `/speak` drops Markdown into `~/Speech/intake`. The independent daemon handles the accepted Qwen Base K2SO voice and laptop playback, during printing’s active hours. No extra model rewrites the answer. Local transcription and TTS inference stay on the coordinator; Claude uses its configured provider. The laptop handles wake, nudge, capture/transport and playback.

A follow-on “Respond” operation needs a separately scoped session-binding policy. Replacing Alexa with “Respond” also requires a suitable trained detector and false-activation tests; changing a label cannot teach the Alexa model a new word. Generic playback suppression and call-recording inhibition remain independent wake requirements.

## Strengths and tradeoffs

**Parakeet-TDT 0.6B v3** is the dedicated recognizer already used by Voxtype. It minimizes new serving and prompt management. NVIDIA documents multilingual recognition, including English and French, but Tom’s accent, code-switching and project vocabulary still need testing. Our ordinary passages and silence worked; “dotfiles” became “the.files.” Names, paths, negation and self-correction matter more than a fluent-looking transcript. [NVIDIA model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).

**Gemma E4B-it** is the strongest Gemma candidate in this small suite. It correctly transcribed the routing utterance and ordinary English clips, faster than 12B. Audio interpretation and destination selection could become useful later. Today those capabilities are unused, while its runtime, matching projector and transcription prompt remain additional dependencies. General models can answer, translate or embellish instead of transcribing.

**Gemma 12B-it** now transcribes these English fixtures correctly after an explicit English-to-English instruction resolved unwanted translations, repetitions and a silence response. Same weights, same runtime: this demonstrates prompt sensitivity, not a defective audio model. French and mixed-language behavior remain unresolved. The separate dense-context routing failure is irrelevant to a thin transcription front end. Google documents a 30-second audio limit for these models; longer commands require tested segmentation. [Google audio guide](https://ai.google.dev/gemma/docs/capabilities/audio).

## The matched evidence and its limits

Using the same saved WAVs, resident Parakeet completed all five probes. Final-audio-frame to delivered-transcript time was 0.55 seconds for the routing request, 0.50 for ordinary speech, 0.55 for the actor and 0.78 for technical speech. The routing WAV took 0.89 seconds through resident E4B HTTP and 2.29 through corrected resident 12B. Parakeet includes a 200 ms loopback tail. Both exclude laptop endpoint detection and network delivery; virtual-microphone capture versus direct WAV ingestion also differs. This favors resident Parakeet on these clips, not yet the complete live experience.

Separate direct Parakeet CLI decoding took approximately 0.30–0.53 seconds, but four of fifteen fresh processes aborted after emitting transcripts, with heap-corruption evidence. Those runs are failures. Reusing resident Voxtype or serving Parakeet directly is a separate implementation choice; fix or avoid the failing lifecycle. Five successful resident probes are not a sustained reliability trial.

The current prototype buffers a whole command, then replays it into Voxtype, adding roughly another utterance duration. That must change: transport audio while Tom speaks and finalize once endpointing finishes. Test the complete path through transcript delivery, Claude acceptance and first audible Qwen answer, with identical downstream components for every recognizer.

Choose Parakeet first, subject to that integration test. Prefer E4B if it improves recognition or response delay on Tom’s speech enough to justify another runtime. Reopen 12B for a concrete audio-understanding requirement. The small fixture set establishes neither population accuracy nor tail latency. Gemma remains parked, not deleted; the proposed complete integration is not yet deployed.
