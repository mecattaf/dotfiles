# Appendix A — Gemma 4 and the local speech stack

Status: technical investigation only. This appendix supplements the printed 2026-08-13 report; it does not replace its recommendation or enable a new service.

Investigation snapshot: 2026-08-14.

## Decision in one page

Gemma 4 is useful here, but not in the way the `any-to-any` label initially suggests.

The released Gemma 4 models accept combinations of text, image, video frames, and—in the E2B, E4B, and 12B Unified variants—audio. They generate **text**, not speech audio. In practical speech terms they are *many-input-to-text* models. They can transcribe, translate, understand an utterance, reason, and emit a tool call or answer, but Qwen3-TTS, Chatterbox, OpenMOSS, or another speech generator is still required to produce the Jarvis or K-2SO voice.

The final stack from the main report therefore remains sound:

```text
Hey Jarvis → Voxtype/Parakeet → Pi or another agent → Qwen TTS → PipeWire
```

Gemma adds two optional agent/understanding lanes:

```text
completed audio turn → Gemma 4 E4B on XDNA2 → text/tool result → Qwen TTS

Parakeet transcript → Gemma 4 26B-A4B on Radeon → text/tool result → Qwen TTS
```

The first lane is especially interesting because FastFlowLM places the language model and its audio encoder on the NPU while the Radeon remains available for TTS. For this machine today, FastFlowLM is the provider of the deployable Gemma NPU2 package. The second lane uses a larger and much more capable model, but it is a GPU/Vulkan GGUF and has no audio input in the current local deployment.

The important placement decisions are:

- **Do not put Gemma in default `/speak`.** The smart agent has already authored the text. A second model would add delay without adding meaning.
- **Keep Parakeet as live ASR.** It is already resident and genuinely streaming. Gemma currently accepts a completed audio attachment, has a 30-second audio limit, and does not expose Parakeet-like partial transcripts, timestamps, or cached streaming state.
- **Evaluate the installed E4B NPU model first.** It is already present, audio-capable, and hardware-complementary to GPU TTS. It may be useful for short audio understanding, speech translation, bounded text polish, and a local fast-path agent.
- **Treat 12B Unified as a later benchmark, not a new dependency.** Its encoder-free design is technically compelling, but no proven Strix Halo deployment exists in the current stack. LiteRT-LM would introduce another GPU runtime.
- **Keep the 26B-A4B GPU model in the agent-brain lane.** The supplied `UD-Q8_K_XL` file is a possible quality A/B against the already selected `Q8_0`; it does not unlock speech input or output.
- **Do not add Gemma 3n.** It explains the on-device lineage and is useful context, but Gemma 4 E4B is its relevant successor and is already installed.

## What each supplied item actually contributes

| Item | What it is | Relevance to speech |
|---|---|---|
| [google/gemma-4-12B](https://huggingface.co/google/gemma-4-12B) | The 11.95B-parameter pretrained base checkpoint, not the chat-tuned assistant | New encoder-free audio/image input architecture; text output only |
| [Google AI Edge laptop article](https://developers.googleblog.com/bringing-gemma-4-12b-to-your-laptop-unlocking-local-agentic-workflows-with-google-ai-edge/) | A LiteRT-LM deployment and agent-harness demonstration | Confirms local OpenAI-compatible chat serving and voice-driven text editing, not TTS |
| [Cue case study](https://deepmind.google/models/gemma/gemmaverse/cue-ai/) | A production dictation-polish pipeline using warm local E4B | Strong evidence for a narrow post-STT helper; it does not use Gemma audio input or speech output |
| [Gemma 3n collection](https://huggingface.co/collections/google/gemma-3n) | The 2025 E2B/E4B on-device predecessor | Establishes PLE, MatFormer, conditional modality loading, and audio-input/text-output lineage |
| [FastFlowLM/Gemma4-E4B-IT-NPU2](https://huggingface.co/FastFlowLM/Gemma4-E4B-IT-NPU2) | Q4_1 NPU2 language weights plus separate audio and vision weights | The immediately testable XDNA2 route on this Strix Halo |
| [Unsloth 26B-A4B UD-Q8-K-XL](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/gemma-4-26B-A4B-it-UD-Q8_K_XL.gguf) | A 27.64 GB high-fidelity GGUF target for llama.cpp | A stronger text/image-capable agent brain on the Radeon; the 26B model has no audio capability |

For an assistant experiment, the 12B checkpoint to compare would be [google/gemma-4-12B-it](https://huggingface.co/google/gemma-4-12B-it), not the supplied pretrained base model. Both full checkpoints contain about 23.92 GB of BF16 model weights.

## “Any-to-any” is not speech-to-speech

The Hugging Face repositories carry an `any-to-any` task tag, but the official model cards are precise: Gemma 4 handles multimodal input and generates text output. The audio features advertised for E2B, E4B, and 12B are:

- multilingual automatic speech recognition;
- speech-to-translated-text translation;
- audio summarization and question answering;
- mixing audio with text, images, or video frames in one prompt;
- reasoning and function calling after the audio has been understood.

There is no waveform decoder, acoustic-token generator, vocoder, voice registry, voice-design prompt, or reference-voice enrollment path. Gemma cannot absorb the K-2SO reference bank and speak in that identity. It can, however, receive a spoken command and decide what a tool or downstream speech engine should do.

This produces a useful three-layer distinction:

| Layer | Current specialist | Gemma 4 contribution |
|---|---|---|
| Hear | streaming Parakeet through Voxtype | Completed-clip ASR, translation, and semantic audio understanding |
| Think and act | Pi/Codex/Claude or a local agent model | Local reasoning, function calls, and small self-contained agent tasks |
| Speak | Qwen3-TTS and cloning/design challengers | None; output remains text |

Gemma can combine the first two layers for a short completed turn. It cannot combine all three.

## The three Gemma 4 deployment lanes

### 1. E4B on the XDNA2 NPU: already present

The declared `gemma4-it:e4b` package is not a generic Hugging Face checkpoint sent to the NPU. It is FastFlowLM’s native NPU2 snapshot, currently owned under `~/.config/flm/models/Gemma4-E4B-IT-NPU2` and invoked request-scoped with `flm run gemma4-it:e4b`.

The local files match the upstream package:

| Payload | Bytes | Purpose |
|---|---:|---|
| `model.q4nx` | 7,142,621,252 | Q4_1 language model |
| `audio_weight.q4nx` | 956,326,424 | Gemma 4 Conformer audio tower |
| `vision_weight.q4nx` | 956,326,592 | vision tower |
| tokenizer and configuration | about 32.2 MB | vocabulary, template, modality configuration |
| **Total** | **9,087,470,597** | installed runtime-owned package |

The local model registry marks it as audio-, vision-, reasoning-, tool-calling-, and chat-transcription-capable. Its default local context is 32K even though the base architecture supports 128K. FastFlowLM’s chat-completions API accepts base64 `input_audio` alongside text and images. Its separate `/v1/audio/transcriptions` route is a different mechanism backed by an additionally loaded Whisper model; Gemma audio understanding itself belongs to `/v1/chat/completions`.

FastFlowLM is now maintained in the AMD ROCm organization and explicitly supports XDNA2 families including Strix Halo. That gives this package a much firmer hardware fit than a generic PyTorch experiment.

#### One local measurement

The existing model was loaded once with the declared request-scoped command; no model was downloaded and no daemon was left running. At the default 32K context and performance power mode:

- cold command-to-prompt readiness was approximately **31 seconds**;
- a 55-token text-polish prompt had **1.48 seconds warm time to first token**;
- reported prefill was **37.18 tokens/s** and decode was **11.88 tokens/s**;
- the 111-token response took roughly nine seconds to decode and offered three rewrites despite a request for one concise sentence.

This is one operational probe, not a quality benchmark. Its decode rate closely matches FastFlowLM’s published E4B result of 12.6 tokens/s at 1K context on a Kraken Point test system. The tiny-prompt prefill number is not comparable with the vendor’s large-prompt throughput table because fixed launch and checkpoint work dominates it.

The result is decisive for `/speak`: starting a request-scoped E4B for every utterance would reproduce the slow `/print` feeling. A warm server could remove the 31-second load, but even the measured warm turn added more than a second before text generation and then generated at about 12 tokens/s. It belongs behind an explicit optional mode until a shorter-output prompt and resident lifecycle are justified by use.

### 2. 26B-A4B on the Radeon: already declared

The active local deployment is:

```text
gemma-4-26B-A4B-it-Q8_0.gguf        26,859,861,728 bytes
MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf  461,766,816 bytes
```

It runs through llama.cpp/Vulkan behind llama-swap. The model has 25.2B total parameters, about 3.8B active parameters per token, 128 routed experts plus one shared expert, and a 256K architectural context. The external MTP drafter shares the target KV cache and can pair with any quantization of the 26B-A4B target.

The supplied `UD-Q8_K_XL` target is 27,636,232,928 bytes—776,371,200 bytes larger than the selected `Q8_0` target. Adding the same recommended Q8 MTP drafter would make the pair 28,097,999,744 bytes. That is a reasonable future fidelity A/B, but both are already eight-bit choices. There is no speech-specific evidence that justifies changing the pinned artifact now.

Upstream 26B-A4B understands text and images, but not audio. The Unsloth repository supplies separate vision projectors; the current dotfiles deployment deliberately roots only the language GGUF and MTP head, so it is text-only in local operation. Its speech role is therefore conventional and useful: Parakeet supplies text, the 26B model reasons or uses tools, and Qwen supplies speech.

### 3. 12B Unified on a new GPU runtime: interesting, not yet placed

Gemma 4 12B Unified removes the separate Conformer and vision towers. Raw 16 kHz audio windows and image patches are projected into the same decoder-only transformer that handles text. The configuration uses 640 audio samples per token, or 25 audio tokens per second. A maximum 30-second clip therefore contributes roughly 750 audio tokens before prompt and output tokens.

The design is elegant because one set of transformer weights can learn across modalities and no large independent encoder must be scheduled. It does not make inference continuous: the published interface still receives an attachment and generates text after processing it. There is no documented streaming-audio state or partial-transcript protocol.

The official LiteRT-LM package is the most practical deployment lead:

- a roughly 6.55 GB Linux/macOS package, or a 5.99 GB GPU/web variant;
- Linux, macOS, and Windows support with Vulkan-compatible GPU acceleration;
- audio attachments through `--audio-backend=cpu|gpu`;
- function calling and an OpenAI-compatible `/v1/chat/completions` server;
- current text and audio support, with vision and MTP still listed as later work for this package.

Google reports 66.26 decode tokens/s, 662.32 prefill tokens/s, and 1.56-second time to first token on a discrete Radeon AI PRO R9700. That benchmark is warm, uses a 2K context and prepared caches, excludes load time, and is **not** evidence for the Strix Halo iGPU. LiteRT-LM is absent from the current Nix deployment, while FastFlowLM and llama.cpp are already owned and pinned. The 12B model should earn a new runtime through a bounded comparison rather than architectural novelty alone.

## What Gemma 3n teaches—and why not to install it

Gemma 3n introduced the mobile-first E2B/E4B pattern:

- Per-Layer Embeddings kept large lookup tables out of scarce accelerator memory;
- MatFormer nested the E2B path inside E4B and permitted smaller execution slices;
- audio and vision parameters could be conditionally omitted;
- the audio path consumed 6.25 tokens per second and produced text;
- total context was 32K.

Gemma 4 retains the effective-parameter idea for its small models, expands the context to 128K, improves reasoning/tool use, and gives E4B a newer audio stack. The installed Gemma 4 E4B is the relevant experiment. Gemma 3n would add another old checkpoint without filling a missing role.

## Consequences for the speech architecture

### `/speak` remains model-free on the fast path

The default path should still be:

```text
authoritative streamed agent text → deterministic oral cleanup → safe clause → warm TTS
```

Cue’s result does not contradict this. Cue performs a different job: cloud STT first produces rough text, then a **warm** local E4B under Ollama applies a compact formatting prompt, and native OS APIs paste the result. Cue measured a median polish latency reduction from 876 ms to 488 ms across 227 voice samples on Apple Silicon. It did not use Gemma’s audio input, did not synthesize speech, and did not cold-start the model per utterance.

That is good evidence for `/speak --polish` or dictation cleanup if an appropriate model is already warm. It is not evidence for putting a side model between a smart agent’s finished answer and the first audible clause.

### Parakeet remains the live transcription path

Gemma should first challenge Parakeet only on bounded completed clips. Parakeet currently offers the properties a live controller needs: resident weights, 320 ms chunks, cached context, progressive text, and a known Voxtype start/stop boundary. Gemma offers richer semantic understanding of the raw clip but not those transport semantics.

A useful hybrid is:

```text
Parakeet partials → immediate UI and endpointing
Parakeet final + optional raw clip → Gemma semantic correction, translation, or tool choice
```

That second pass must be optional or asynchronous. Waiting for it before every agent turn would add another serial latency stage.

### Pi remains the harness

The model still speaks to an agent harness through text and structured events. Gemma does not own sessions, tool execution, cancellation, microphone state, or playback. Pi remains a good first harness because it already supplies those agent semantics.

- The GPU 26B model is already reachable through the OpenAI-compatible llama-swap boundary and can be selected as a Pi model.
- FastFlowLM can expose E4B through OpenAI-compatible chat completions, including `input_audio`, but current machine doctrine intentionally uses `flm run` and leaves no resident server.
- LiteRT-LM could expose 12B through the same chat shape, but adds an unproven runtime.

For realtime E4B use, the actual architectural decision is therefore not “Can Pi call Gemma?” It can. The decision is whether a 9.1 GB FastFlowLM server should remain warm on the NPU. That requires measured usage frequency, idle power, wake-to-answer latency, and coexistence with other NPU utilities.

### Lemonade Mobile still needs the narrow gateway

The phone result is unchanged. Lemonade Mobile’s current loop expects transcription, chat completion, and speech generation as three services. Gemma can supply chat, and FastFlowLM can accept audio inside chat, but neither Gemma nor LiteRT-LM supplies the required speech-generation endpoint. FastFlowLM’s transcription endpoint uses separately loaded Whisper rather than turning the Gemma chat model into a drop-in transcription server.

Changing the mobile client to send raw audio directly to E4B could become an experiment, but it would sacrifice the app’s existing partial/final ASR flow and still require Qwen TTS. The thin Tailscale gateway remains the clean integration point.

### Speech translation gains one useful challenger

Gemma E4B and 12B can translate a source utterance directly into target-language text. The speech-to-speech chain would be:

```text
source audio → Gemma translated text → target-language Qwen TTS
```

This is a useful local challenger to Parakeet/text translation and Seamless M4T, especially for short mixed-language turns. It still discards source prosody and speaker identity at the text boundary, so it is not an expressive voice-preserving translator.

## Bounded experiment order

No new model should be downloaded for the first round.

### G0 — installed E4B audio understanding

Use `flm run gemma4-it:e4b` directly, as required by the current NPU lifecycle. Test held-out 5-, 15-, and 29-second clips in English, French, and mixed speech. Record:

- cold prompt readiness and warm time to first token;
- exact-match/WER against the same clips in Parakeet;
- names, numbers, punctuation, and code/path transcription;
- direct speech translation quality;
- semantic questions that plain ASR cannot answer;
- NPU utilization, package power, resident memory, and release-on-exit;
- behavior at the 30-second limit and on silence/noise/music.

### G1 — dictation polish, separately from `/speak`

Use 50 real raw transcripts and a strict short-output prompt. Compare no polish, E4B polish, and the smart agent’s own prepared text. Measure fidelity, omissions, over-editing, warm latency, and cold latency. Promote only if the mode is explicit or the model is already warm for another reason.

### G2 — agent fast path

Give Pi a bounded local profile with a small tool set and compare E4B NPU with the existing 26B-A4B GPU route on short self-contained commands. The NPU model’s value is hardware separation and locality, not parity with the larger brain. Measure tool-call validity, answer brevity, interruption, and end-to-first-audio through Qwen.

### G3 — 12B Unified only if E4B reveals a real gap

Use a disposable pinned LiteRT-LM environment and the 12B instruction checkpoint. Compare only the tasks where E4B failed but direct audio understanding remained desirable. A Strix Halo result must include cold load, warm TTFT, audio prefill, decode, memory, GPU/TTS contention, and the exact modality subset supported by that build.

### G4 — optional 26B quantization A/B

Compare the current Q8_0 target with `UD-Q8_K_XL` under the same Q8 MTP drafter. Keep prompts, context, sampler, and llama.cpp build identical. Change the pinned artifact only for a demonstrated quality or reliability gain; the larger file alone is not a speech feature.

## Updated final recommendation

Gemma 4 earns an **experimental input-and-brain branch**, not a replacement stack.

1. Ship `/speak` as already designed: no default side model, streamed safe clauses, Qwen-first TTS.
2. Keep Voxtype/Parakeet as the authoritative realtime transcript source.
3. Evaluate the already-installed E4B NPU package for completed-audio understanding, translation, explicit polish, and bounded local-agent tasks.
4. Keep the 26B-A4B GPU model as a larger text brain available to Pi through llama-swap.
5. Do not add 12B Unified or Gemma 3n until the E4B experiment identifies a concrete unmet need.
6. Keep Qwen/Chatterbox/OpenMOSS voice work unchanged: Gemma 4 has no speech-output or voice-cloning path.

The architectural opportunity is real: **NPU hearing/thinking beside GPU speech generation**. The current implementation evidence says to exploit that separation selectively, not to insert a cold multimodal model into every spoken turn.

## Primary technical sources

- [Gemma 4 12B model card](https://huggingface.co/google/gemma-4-12B) and [instruction-tuned variant](https://huggingface.co/google/gemma-4-12B-it)
- [Gemma 4 technical report](https://arxiv.org/abs/2607.02770)
- [Gemma audio-understanding guide](https://ai.google.dev/gemma/docs/capabilities/audio)
- [Gemma 3n architecture overview](https://ai.google.dev/gemma/docs/gemma-3n)
- [FastFlowLM E4B NPU2 model package](https://huggingface.co/FastFlowLM/Gemma4-E4B-IT-NPU2), [runtime](https://github.com/ROCm/FastFlowLM), [API examples](https://fastflowlm.com/docs/instructions/server/openapi/), and [NPU benchmark](https://fastflowlm.com/docs/benchmarks/gemma4_results/)
- [LiteRT-LM 12B package and benchmark](https://huggingface.co/litert-community/gemma-4-12B-it-litert-lm), [multimodal CLI](https://developers.google.com/edge/litert-lm/cli/usage), and [OpenAI-compatible server](https://developers.google.com/edge/litert-lm/cli/openai_server)
- [Unsloth 26B-A4B GGUF repository](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF) and [MTP drafter notes](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/MTP/README.md)
- [Cue’s Gemma 4 dictation-polish case study](https://deepmind.google/models/gemma/gemmaverse/cue-ai/)
