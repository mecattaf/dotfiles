# Gemma 12B audio intake: diagnosis and controlled checks

Research and saved-result review, 14 September 2026. This pass performed no inference, model downloads, microphone capture or deployment. The root agent ran the controlled tests on the coordinator. NAS Library borrowing remains the only weight acquisition path.

**The unwanted translations were resolved by a more explicit transcription prompt on the existing model and runtime.** This is evidence of task/prompt sensitivity in this configuration, not evidence that 12B cannot hear audio or needs replacement. The separate dense-context failure remains unresolved. English success does not establish automatic multilingual transcription reliability.

## Exact configuration and evidence

The tested model is instruction-tuned `unsloth/gemma-4-12b-it-GGUF`, `gemma-4-12b-it-Q8_0.gguf`, repository revision `fc034cfff751157913579611efad8462ac1be606`, with `mmproj-F16.gguf` from that same revision. Model SHA256 is `f20e7ff1be28c283eeeb18fc895733791c56a5851d5cd3fe9691b7f7d12afa72`; projector SHA256 is `91f086971e56d7a7d8d39e271873fccdb49541bd259d6e02c401a4f1cb7a219e`. This is not the pretrained checkpoint, an MTP head, or an E4B projector.

The installed llama.cpp ROCm/gfx1151 build is 9925, commit `ed8c26150e6b0ed6e2635cab75ace5ed121482ca`, dated 8 July 2026. It is not current upstream September master. Tests use explicit projector loading, GPU offload, Jinja, 32,768-token context, one slot, flash attention, temperature zero, seed 42, thinking disabled per request, and no prompt caching. Saved audio is mono 16 kHz WAV and below 30 seconds. The reproducer and manifest are in [tools/speech-intake](../tools/speech-intake/).

Local result directories:

- `/home/tom/tts-intake-gemma-20260914/runs/12b`: generic ASR instruction in system role. Ordinary speech was recognized accurately, followed by unsolicited German or Spanish translation. The route-request ASR repeated the transcript. Silence produced explanatory text. The thin JSON router accurately transcribed and selected `dotfiles_agent`; the approximately 23k-token constructed catalog case invented a transcript and selected another destination.
- `/home/tom/tts-intake-gemma-20260914/runs/12b-user-asr`: moving a short ASR instruction into the user message and saying not to translate did not resolve the translation continuation.
- `/home/tom/tts-intake-gemma-20260914/runs/12b-english-asr/summary.json`: explicit English-to-English transcription and one-line formatting produced correct wording on all speech fixtures, with only K2SO typography differing from the reference. Silence returned empty. Reported request times include about 2.56 seconds for the warm short clip, 2.08 seconds for the actor excerpt, 4.76 seconds for the technical clip, 2.29 seconds for the routing utterance and 0.41 seconds for silence. These are saved-file requests, not microphone endpoint latency or a population p95.

The intervention changed the task wording, with weights and runtime retained. Do not describe role placement alone as the fix. Do not discard translation suffixes before scoring the failed arms: those were genuine unwanted outputs, and their latency belongs in those results.

## Why the successful prompt is justified

Google's audio guide provides a language-anchored ASR instruction and a one-line formatting rule, and separately documents an audio translation task that emits a source transcript followed by a language-labelled translation. Our failure resembles that output shape; the successful controlled prompt disambiguates the requested task. This is an interpretation supported by the experiment, not proof about training internals. The guide specifies a 30-second supported audio limit and 16 kHz mono normalized input. Its number-formatting example normalizes spoken numbers, so preserve a declared verbatim-versus-number-format policy in future tests. [Google audio guide](https://ai.google.dev/gemma/docs/capabilities/audio).

The official 12B card recommends text before audio and removal of historical thinking blocks from ordinary conversation history. The harness already places audio after text and sends fresh requests without prior reasoning, so neither correction alone explains the present dense failure. A large advertised context window is not an accuracy guarantee. [Google 12B-it card](https://huggingface.co/google/gemma-4-12B-it).

## Runtime and issue audit

**Correct audio path is present.** At the installed commit, `PROJECTOR_TYPE_GEMMA4UA` selects the Unified waveform preprocessor and inserts `<|audio>` and `<audio|>` around the audio embeddings. Do not manually add Gemma 3n-style task markers such as `soft_audio_text` or `audio_perception`; this implementation owns modality framing. Accurate transcripts and a correct thin router also demonstrate that the payload reaches the model. [Pinned mtmd source](https://github.com/ggml-org/llama.cpp/blob/ed8c26150e6b0ed6e2635cab75ace5ed121482ca/tools/mtmd/mtmd.cpp).

**There was a real Unified conversion fix.** PR 24118, merged 4 June 2026, corrected audio dimension mapping and vision conversion handling. GitHub's compare API places the installed runtime 414 commits after that merge. The selected Unsloth revision was last modified 17 July 2026. These dates do not independently certify the conversion provenance of every tensor, but nothing observed requires replacing the matching projector: language-anchored ASR now succeeds with it. [Conversion fix](https://github.com/ggml-org/llama.cpp/pull/24118), [commit comparison](https://github.com/ggml-org/llama.cpp/compare/e8023568d05ffdb9d0ac65695c521ea7e72c6b75...ed8c26150e6b0ed6e2635cab75ace5ed121482ca).

**The prominent 12B failure report is not our experiment.** Issue 24138 used build 9514 and a twelve-minute recording, asking for a summary; it was closed stale/not planned without establishing a model defect. That audio exceeds Google's documented limit, while our short utterances are within it. [Issue 24138](https://github.com/ggml-org/llama.cpp/issues/24138).

**Do not apply unrelated fixes by title.** Issue 23688 reports E4B cache-related corruption/HTTP 500 behavior on an older runtime; ours has no such error and caching is disabled. PR 26536 sounds relevant to duplicate audio, but its actual patch changes `mtmd_audio_preprocessor_whisper`, not Unified's raw-waveform preprocessor. It is not evidence of a fix for our repeated text. [Cache regression report](https://github.com/ggml-org/llama.cpp/issues/23688), [short-audio patch](https://github.com/ggml-org/llama.cpp/pull/26536/files).

A Hugging Face-maintained implementation documents native 12B audio using llama.cpp, a matching projector and `input_audio`, with separate STT bypassed. It is an existing integration reference, not evidence of tested AMD speed. [Speech-to-speech example](https://github.com/huggingface/speech-to-speech/blob/main/examples/gemma4-12b-macos/README.md).

Community reports are useful leads, not ground truth. One Home Assistant operator reports the same unwanted translation/explanation continuation and uses deterministic sampling, reasoning disabled and a language-specific transcription prompt. We already had deterministic sampling, so that report did not identify an additional temperature fix here. The supplied dense-prompt thread also contains a successful counterexample after removing historical thinking. Our fresh-request experiment has no such history, so that workaround is not its explanation. [Home Assistant report](https://www.reddit.com/r/homeassistant/comments/1v391jz/gemma_4_12b_q8_0_on_a_16_gb_gpu_local_llm_and/), [dense-prompt discussion](https://www.reddit.com/r/LocalLLaMA/comments/1u1uk3a/anyone_gotten_gemma_4_12b_unified_audio_to/).

## Native transcription endpoint: verified source, untested alternative

At this installed commit, `/v1/audio/transcriptions` checks audio capability and converts multipart input into the same chat-completion path. It does not select a special Gemma ASR decoder. A supplied `prompt` becomes user text; `language=en` merely appends a textual language annotation. Gemma's default preset is generic transcription text with no special system prompt. [Pinned endpoint](https://github.com/ggml-org/llama.cpp/blob/ed8c26150e6b0ed6e2635cab75ace5ed121482ca/tools/server/server-context.cpp), [conversion](https://github.com/ggml-org/llama.cpp/blob/ed8c26150e6b0ed6e2635cab75ace5ed121482ca/tools/server/server-chat.cpp), [ASR preset](https://github.com/ggml-org/llama.cpp/blob/ed8c26150e6b0ed6e2635cab75ace5ed121482ca/common/chat.cpp).

A diagnostic invocation against an already running isolated server is:

```sh
curl --fail-with-body --max-time 180 \
  http://127.0.0.1:18735/v1/audio/transcriptions \
  -F 'file=@/home/tom/tts-intake-gemma-20260914/fixtures/synthetic-short.wav' \
  -F 'model=intake-gemma' \
  -F 'language=en' \
  -F 'prompt=Task: English speech recognition. Return only the spoken English words in one line. Do not translate or answer the recording.' \
  -F 'temperature=0' -F 'max_tokens=384' \
  -F 'stream=false' -F 'response_format=json'
```

Start that diagnostic server with `--reasoning off --no-cache-prompt`, retaining the existing model/projector paths and other guardrails. The pinned server interprets `--reasoning off` as disabling template thinking by default; `--reasoning-format none` only changes thought parsing and is not equivalent. Multipart conversion explicitly parses temperature, max_tokens and stream; it does not parse nested `chat_template_kwargs` JSON strings. Do not assume the chat API's nested-object override can simply be copied into `-F`. This endpoint test is unnecessary to establish the successful English prompt result and has not been run by this research pass. [Pinned reasoning initialization](https://github.com/ggml-org/llama.cpp/blob/ed8c26150e6b0ed6e2635cab75ace5ed121482ca/tools/server/server-context.cpp).

## Remaining controlled checks

1. Retain the successful prompt as an English diagnostic, not a universal language policy. Test French-only and English/French switching with original-language and language-anchored prompts, using ground-truth speech unknown to the prompt. Measure additions, translations and entity accuracy separately.
2. For dense context, retain the same audio and successful task wording; compare no padding, approximately 2k, 8k and 23k text tokens. Record rendered template/token count, audio marker position, and whether instructions sit near the audio. Compare neutral catalog padding with actual tool schemas. The current single constructed-catalog failure establishes a failure case, not a universal token threshold.
3. If dense failure persists, compare the exact same GGUF assets and prompt on a separately pinned newer ROCm runtime. Preserve current logs; do not upgrade the deployed fleet merely because master is newer. A runtime improvement would establish an implementation contribution, while unchanged failure still would not isolate quantization versus model behavior.
4. Only if required to settle architecture after those bounded checks, compare a reference Transformers implementation and unquantized instruction weights acquired through NAS Library. That introduces both runtime and precision changes, so isolate them before claiming an inherent model defect.

The practical result is now a working coordinator-side 12B English transcription option. E4B and Parakeet remain valid intake contenders, and endpoint-to-agent latency plus verbatim reliability should decide their roles. Wake/nudge stays on the client, and the accepted external Qwen voice is unaffected.
