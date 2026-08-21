# Engines, models, and the Strix Halo fit

## Existing baseline

The machine already has an unusually good speech foundation:

- **Live English ASR:** Voxtype owns `parakeet-unified-en-0.6b` through ONNX/MIGraphX with cached streaming context. Do not replace it merely to make a demo repository self-contained.
- **Long-form ASR:** VibeVoice ASR is already represented in the local model inventory and call-diarization work.
- **Long-form TTS weights:** the current `vibevoice-large-bf16` artifact is the same [`aoi-ot/VibeVoice-Large`](https://huggingface.co/aoi-ot/VibeVoice-Large) model used by Kyuz0’s Strix Halo toolbox.
- **NPU utility inference:** FastFlowLM is request-scoped and separately owned. Tiny wake models do not automatically benefit from being moved onto the NPU.
- **Unified memory:** it makes large models possible, but is not a reason to keep every ASR, TTS, and music model resident.

The existing weight sizes also correct the intuition that everything is “quite small”: Parakeet is about 2.5 GB locally, VibeVoice ASR about 17.3 GB, and VibeVoice Large TTS about 18.7 GB. Several engines can coexist on disk; simultaneous residency and bandwidth contention still need measurement.

## Candidate roles

| Candidate | Best question it answers | Voice control | Strix route | Current judgment |
|---|---|---|---|---|
| Qwen3-TTS 0.6B/1.7B | Can one engine provide designed identity, cloning, and low-latency speech? | Built-ins, reference cloning, 1.7B voice design | C++ Vulkan implementations; Python/ROCm comparison | First evaluation priority |
| Chatterbox | How good is short-reference identity enrollment? | Zero-shot reference; expressive controls vary by model | ROCm/PyTorch, community hybrid, `audio.cpp` | Strong cloning challenger |
| OpenMOSS/MOSS-VoiceGen | Can cloning and free-text voice design share one API? | Reference clone and text design | standalone GGML C++ Vulkan/ROCm or Lemonade adapter | High-value challenger, fast-moving |
| OmniVoice | Can a compact model deliver realtime cloning quality? | Reference cloning | emerging `audio.cpp` path | Promising; community results need reproduction |
| VibeVoice Large | How well does long-form/multi-speaker synthesis hold together? | Presets and custom WAV conditioning | Kyuz0 ROCm recipe; local weights exist | Long-form specialist, not first low-latency daemon |
| Kokoro | What is the small fixed-voice latency/control floor? | Fixed voices | CPU/ONNX and multiple servers | Excellent baseline, not identity target |
| Supertonic | What does a very small multilingual ONNX engine achieve? | Fixed/designed profiles; exact local builder/API needs checking | ONNX | Fast baseline candidate |
| `audio.cpp` | Can one C++ harness compare many audio architectures consistently? | Depends on model | Vulkan mature, HIP evolving | Evaluation harness; avoid premature monolith |
| ACE-Step | Can the box generate songs/music? | Music prompting/conditioning | Strix community recipes | Separate product lane, not TTS |

## Qwen3-TTS

The official [`QwenLM/Qwen3-TTS`](https://github.com/QwenLM/Qwen3-TTS) family is the most direct match for the intended assistant:

- Base models support reference voice cloning.
- The 1.7B VoiceDesign model creates a voice from an attribute instruction.
- The documented design-then-clone workflow can create an original seed voice and then reuse it consistently.
- 0.6B and 1.7B sizes permit a quality/latency comparison rather than one all-or-nothing deployment.

Two C++ efforts are worth testing independently rather than treating “Qwen C++” as one result:

### `ServeurpersoCom/qwentts.cpp`

[`qwentts.cpp`](https://github.com/ServeurpersoCom/qwentts.cpp) currently exposes named speakers, reference cloning, voice design, streaming, Q8/Q4 quantization, Vulkan builds, a C ABI, and an OpenAI-compatible speech server. Pre-encoded speaker/codec artifacts make it attractive for a real voice registry.

### `khimaros/qwen3-tts.cpp`

[`qwen3-tts.cpp`](https://github.com/khimaros/qwen3-tts.cpp) is a narrower upstream-GGML implementation with a single CMake/Vulkan path, CLI/server, streaming state, Q8/F16, reference conditioning, and 1.7B voice design. Its current server exposes OpenAI-compatible `/v1/audio/speech` and `/v1/audio/voices`, multipart voice enrollment, and genuinely chunked PCM vocoder output while the transformer is still generating. The Strix Halo community speed report is useful but remains an anecdote until reproduced with identical text, voice, output settings, and first-audio measurement.

The screenshot comparison supplied in this investigation captures a real tradeoff: `ServeurpersoCom` has the broader public API and quantization/registry surface; `khimaros` has a simpler build and integrated HTTP server. The benchmark should evaluate both, not select by stars.

For `/speak` and conversation, first-audio streaming and reusable enrollment artifacts matter more than total-file time alone. A server that returns one complete WAV can sound slow even when its realtime factor is excellent.

## Chatterbox

[`resemble-ai/chatterbox`](https://github.com/resemble-ai/chatterbox) offers compact variants and short-reference zero-shot cloning. Its role here is to **enroll a controlled reference recording**, then measure identity, stability, prosody, and Strix acceleration. A clean 10–30 second recording is much more useful than hours of dialogue mixed with music and effects.

Candidate execution paths include a dedicated ROCm/PyTorch environment, an AMD community hybrid server, and [`audio.cpp`](https://github.com/0xShug0/audio.cpp). None should be merged into the global Python environment.

## OpenMOSS and Lemonade

The official [`OpenMOSS/MOSS-TTS`](https://github.com/OpenMOSS/MOSS-TTS) family includes speech cloning and voice design and is developing rapidly. [`pwilkin/openmoss`](https://github.com/pwilkin/openmoss) is the relevant standalone GGML C++ implementation with Vulkan/ROCm and an OpenAI-compatible speech endpoint.

Lemonade’s current `/v1/audio/speech` contract is interesting because it presents:

- Kokoro fixed voices and PCM streaming;
- OpenMOSS cloning through `reference_wav_b64`;
- MOSS VoiceGen free-text voice/style instructions;
- the familiar OpenAI request shape.

But [`lemonade-sdk/lemonade`](https://github.com/lemonade-sdk/lemonade) is a broad model/runtime control plane, not merely a speech adapter. The dotfiles deliberately leave it disabled, and the machine already has carefully separated llama-swap, FastFlowLM, Voxtype, and model ownership. Lemonade Mobile’s useful phone loop needs only three OpenAI-shaped routes and does not force server adoption. The correct conclusion is:

> Preserve Lemonade’s useful API shape and test its speech backend in a bounded environment; do not adopt the whole platform until it wins on lifecycle, reproducibility, security, and coexistence.

“AMD sponsored/community maintained” is more accurate than treating it as an official AMD product boundary. If ever promoted, it should be pinned and Nix-owned, with no silent runtime model downloads and no authority over unrelated LLMs.

## VibeVoice and Kyuz0

[`kyuz0/amd-strix-halo-voice-toolbox`](https://github.com/kyuz0/amd-strix-halo-voice-toolbox) is valuable because it proves a specific Strix Halo path for the exact VibeVoice Large artifact already present locally. It uses Fedora Toolbox, Python 3.13, gfx1151 ROCm/TheRock PyTorch, ROCm flash attention, Kyuz0’s VibeVoice fork, and compatibility workarounds for a numba/LLVM collision. It also accepts custom WAV voice conditioning.

That makes the repository an excellent **executable bill of materials and patch oracle**. It is not a reason to replace the Nix architecture with Toolbox. The dependencies, pins, environment shims, and patches should be translated into an isolated Nix-owned runtime if VibeVoice wins its long-form tests.

Kyuz0’s broader Strix Halo work is worth continuing to monitor because it is close to this hardware and frequently exposes the exact gfx1151 packaging gap. One local distinction must remain: do not copy Fedora advice to disable IOMMU. This machine’s XDNA/NPU path relies on translated IOMMU mode.

## ASR and translation

Parakeet and VibeVoice ASR have different jobs:

- **Parakeet/Voxtype:** low-latency live English command and dictation path.
- **VibeVoice ASR:** long recordings, diarization, and batch work where its larger footprint can be justified.

The AMD [`Real-Time Speech-to-Speech Translation`](https://developer.amd.com/playbooks/speech2speech-translation/) playbook is current enough to be useful as a gfx1151/ROCm environment reference, but its demo is not actually a conversational realtime stack. It loads [`facebook/seamless-m4t-v2-large`](https://huggingface.co/facebook/seamless-m4t-v2-large), consumes a complete WAV, calls `generate`, and writes another WAV. It has no streaming session, interruption, turn state, or speaker-identity preservation.

SeamlessM4T therefore belongs as an optional **translation bridge** after capture, not as the core agent architecture.

## Packaging doctrine

- One owner for every model artifact and cache path.
- Pinned revisions and hashes; no model download during service startup.
- Per-engine Nix environment or service, not one Python environment containing all audio projects.
- Loopback-only inference endpoints by default.
- Lazy/on-demand residency for large specialists.
- Stable northbound speech API and logical voice IDs.
- Benchmarks record exact commit, model hash, quantization, driver/runtime, text corpus, voice reference, native sample rate, and route.

“Stacking” should mean composing services and keeping alternatives available, not keeping 50+ GB of specialists active at the same time.
