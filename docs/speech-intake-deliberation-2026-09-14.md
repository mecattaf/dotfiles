# Speech intake: independent deliberation, 14 September 2026

**Recommendation:** preserve a literal transcript and send it to an explicitly selected active agent. Compare the established Parakeet/Voxtype route with Gemma E4B and 12B under a tiny ASR prompt before choosing the transcription engine. A short Gemma delegator is a separate option for selecting destinations; a dense one-pass audio agent remains a valid experiment, not a proven failure or the default architecture.

This is an architecture assessment, not a benchmark result or activation plan. The parent task owns coordinator GPU tests and model borrowing. No model inference, microphone capture, downloads, or service changes were performed for this assessment. Web sources were checked on 14 September 2026; upstream examples describe their own environments, not verified compatibility with this deployment.

## Constraints and existing evidence

[Mykonos annotations](../../notes/mykonos/annotations-local.md) require “VERBATIM ONLY” and describe one narrow delegator to a stronger agent. The [index](../../notes/mykonos/index.md) distinguishes Tom’s annotations from proposals. Current [AGENTS.md](../AGENTS.md) and subsequent user rulings settle these boundaries:

- The laptop handles Alexa/openWakeWord CPU detection, the listening nudge, and necessary capture, transport and playback. All locally hosted LLM steps in this speech/intake flow run on the **coordinator**, including either Gemma and any router. This proposal has no worker-Halogen dependency and does not relocate existing fleet services.
- Capture is tied to the iContact Camera Pro; absence suspends intake. Call recording inhibits wake and flushes stale audio. Wake/nudge, transcription, session delivery and Qwen speech output remain separately observable stages.
- Qwen Base provides the selected single voice externally to the agent. AMD NPU work stays retired. Brightness is not a listening gate.
- `/speak` is a separate output action: an atomic Markdown drop into `~/Speech/intake`, quiet from 00:00 to 06:00, with no extra LLM rewriting pass.

The worktree [voxtype-relay](../home/dot_local/bin/voxtype-relay) still describes a loopback-sink transport and a batch recording lifecycle. That is source evidence only: this review did **not** establish that the installed relay is identical. Its comments and sleeps are not measured current latency. Verify the live revision and actual ASR checkpoint before using it as the baseline. Voxtype upstream supports several engines and output methods, so “Voxtype” alone specifies neither language coverage nor the decoder. [Voxtype source and engine documentation](https://github.com/peteonrails/voxtype).

## Four mechanisms

| Mechanism | Useful property | Main cost or failure to test | Recommended role |
| --- | --- | --- | --- |
| Parakeet/Voxtype → literal text → active Codex/Claude | Reuses established transcription and keeps the agent’s existing context; transcript can be corrected independently | Names, code-switching and supported languages depend on the exact checkpoint; output transforms and transport can alter text | Baseline and practical fallback; disable optional polishing/replacements for a verbatim comparison |
| Gemma E4B or 12B → literal text → active agent | Native audio recognition with a small, fixed task; same downstream adapter as Parakeet | May paraphrase, answer the utterance, hallucinate on silence, or spend time loading/decoding; transcription must be evaluated, not inferred from general model quality | Direct contender if measured accuracy and endpoint-to-delivery latency justify it |
| Short Gemma audio delegator → one narrow tool → agent | Can select a destination without loading all agent tools/context into the audio prompt | Combines transcription and intent errors; generated summaries can erase qualifiers; route selection adds latency when a destination is already bound | Optional unbound-command mode; bypass it for ordinary dictation into a selected session |
| Audio + dense instructions/tools/history → one Gemma response or tool call | Can eliminate a separate ASR pass and reason directly over speech | Prompt prefill, audio integration, history formatting and tool correctness interact; harder to isolate lost words from wrong reasoning | Controlled experimental arm; do not reject it from the Reddit anecdote |

A delegator should have one schema-constrained dispatch operation, an allowlist of destinations, and an utterance ID. Preserve its transcript separately from its route decision; dispatch must carry the original transcript/audio reference rather than replacing it with a summary. Ambiguous/no-speech input stays pending or empty. It should not acquire a shell tool. Existing agent authorization rules continue to govern consequential actions; speaking a request does not silently change those rules. A model’s self-reported confidence is not calibrated ASR confidence.

## What is actually documented

Google documents native audio recognition for E4B and 12B, with **30 seconds maximum audio**, mono 16 kHz input and 25 audio tokens per second. Longer dictation therefore needs an explicitly tested segmentation policy; a large text context does not establish longer supported audio. The suggested transcription prompt normalizes numbers, so even that recipe needs a declared formatting policy for “verbatim.” Start with preserved wording and evaluate formatting separately. [Google audio guide](https://ai.google.dev/gemma/docs/capabilities/audio).

The 12B Unified architecture projects audio directly without E4B’s separate audio encoder. Google recommends audio after text, and removing previous-turn thinking from ordinary history, with an exception for tool-call turns. Its context capacity is not an accuracy guarantee for audio mixed with dense instructions. [Official 12B-it card](https://huggingface.co/google/gemma-4-12B-it).

The local [registry](../lib/local-models.nix) declares 12B Q8 and a matched **MTP head**, not a Gemma multimodal projector. MTP supports speculative token prediction; it does not provide the audio input path. Encoder-free architecture does not mean that this GGUF runtime requires no separate multimodal artifact: Hugging Face’s documented native-audio example loads the 12B model **and** projector through llama.cpp, uses `input_audio` with STT bypassed, and identifies the old-runtime `gemma4uv` projector error. That example targets Apple Silicon; its protocol and lifecycle are useful references, not an AMD compatibility result. [Native-audio implementation](https://github.com/huggingface/speech-to-speech/blob/main/examples/gemma4-12b-macos/README.md).

The same project documents the separate Parakeet → text LLM → Qwen arrangement, including a text-only Gemma configuration with the projector disabled. These are existing implementations of both architectural choices; adopting their entire server, model downloads or TTS stack is unnecessary here. [Hugging Face speech-to-speech](https://github.com/huggingface/speech-to-speech#combining-with-llamacpp).

The supplied Reddit author reports degraded audio use with roughly 21k tokens across three runtimes. A reply reports improvement after excluding historical thinking, consistent with Google’s documented history rule. Neither report supplies a controlled local replication. Treat prompt density, history contamination and modality handling as competing hypotheses, not an inherent 2k/4k/21k architecture threshold. [Original discussion and counterexample](https://www.reddit.com/r/LocalLLaMA/comments/1u1uk3a/anyone_gotten_gemma_4_12b_unified_audio_to/).

## Delivery into an active session

Bind a stable destination/session ID when capture starts; do not infer the destination from whatever terminal happens to have focus at completion. Keep an utterance ID, capture/endpoint timestamps, literal transcript and delivery receipt. Canceled recordings must not dispatch later. A disconnected transport with an unknown delivery outcome needs reconciliation, not blind replay that could duplicate a command.

Codex App Server documents `turn/start` for a selected thread and `turn/steer` for its active turn, with `expectedTurnId` guarding stale steering. `thread/resume` opens saved history. These APIs are promising for an integration that owns the relevant server connection; their existence does **not** prove this running Codex interface exposes an attachable endpoint. [Official App Server protocol](https://developers.openai.com/codex/app-server/).

Claude’s documented `--resume` continues a named session in a programmatic invocation. It is not evidence that starting another CLI process can safely inject into an already-running interactive owner. For either product, verify the session adapter independently of ASR. Until verified, a transcript ready for explicit submission is preferable to automatic paste-plus-Enter into an arbitrary terminal. [Claude programmatic sessions](https://code.claude.com/docs/en/headless).

The downstream session’s provider remains its existing configuration; placing the local speech adapter and Gemma on the coordinator does not imply that Claude or OpenAI model weights are locally hosted.

## Bounded reproducibility matrix

Use the same saved audio bytes and endpoint boundaries across contenders; do not run tools with real effects. Run minimal ASR first, then a one-tool delegator, then dense prompts with approximately 2k, 8k and the anecdote’s 21k **actual rendered tokens**. At dense sizes compare neutral padding with real instructions/tools, and first-turn with correctly formatted multi-turn history. Keep audio after text as the documented baseline; test other placement only as a named diagnostic.

| Probe | Measure | Failure that should remain visible |
| --- | --- | --- |
| Ordinary speech, repetitions, self-correction | Raw transcript, normalized WER, omitted/inserted words | Polishing that hides a correction or answers instead of transcribing |
| Names, project terms, digits and spoken file paths | Exact entity/string accuracy alongside WER | Plausible substitutions; normalization that changes identifiers |
| English/French switches within one utterance | Per-span wording and language preservation | Translation or language selection hiding lost words; checkpoint language mismatch |
| Silence, room noise, truncated or interrupted speech | Nonempty output and dispatch count; retained partial words | Invented speech or a valid-looking route without a spoken command |
| Audio nonce absent from the text prompt; audio replaced with silence | Correct nonce recall and output change | Text-only success masking an ignored or malformed audio payload |
| Short ASR vs one-tool vs dense context, same utterance | Verbatim accuracy separately from route/schema accuracy | Correct intent with wrong transcript, or correct words routed incorrectly |
| Endpointing and session receipt | End-of-speech → endpoint → transcript complete → route/session acceptance | A fast model hiding a long VAD wait, loading delay or failed handoff |

Record model/checkpoint/projector hashes, runtime commit, GPU backend/offload, rendered template, thinking mode, sampling/seed, output cap, prior history, actual input tokens, audio duration/format/hash and truncation indicators. A successful text response alone does not prove audio was processed. Disable MTP for the first correctness comparison or keep its setting explicit, then assess it separately. Multimodal llama.cpp remains an actively changing subsystem, making runtime pins consequential. [Upstream multimodal notes](https://github.com/ggml-org/llama.cpp/blob/master/tools/mtmd/README.md).

Report cold loading and warm resident latency separately; record GPU contention with Qwen. Measure endpoint latency from annotated speech end, including annotation uncertainty, and use repeated utterances for median/p95 rather than one sample. For one-pass audio compare correct route acceptance directly, not merely time to a first token. Keep the listening nudge and eventual audible Qwen response as separate timestamps. Avoid silent retries through several models: report fallback and its added latency explicitly.

## Separate `/speak` output contract

The agent writes the intended speech once. A proposed `/speak` action publishes that Markdown into `~/Speech/intake` through a same-filesystem temporary file and atomic rename, with an ID and durable receipt. A consumer can perform deterministic Markdown-to-readable-text conversion and Qwen synthesis without asking a second LLM to summarize or stylize it. Preserve the submitted Markdown for review.

Use Europe/Paris for the requested 00:00–06:00 quiet interval. Proposed behavior is to retain queued documents during quiet hours and begin eligible playback after 06:00; do not discard them. Serialize playback, honor cancellation and use the existing playback/microphone inhibition handshake. This is an output queue contract, independent of which ASR or routing mechanism wins; no daemon is implemented by this document.
