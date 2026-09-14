# Qwen TTS build plan

Started 2026-09-14. Worktree `dotfiles-qwen-tts-zenbook`, branch
`work/qwen-tts-zenbook`. Tom approved building from the September 14 brief.

## 1. Reproducible engine and weights

- Package `qwentts.cpp` at `71ad93d591a2811f35db77e27c02acba091c9e9b`
  and its exact GGML submodule with Vulkan, without native CPU build flags.
- Build and exercise the CLI and server on the coordinator's Radeon 8060S.
- Catalog 1.7B Base Q8, 1.7B VoiceDesign Q8 and the matching F32 codec in
  the NAS Library. Download through `library-fetch`, then explicitly borrow
  onto the coordinator. Weights remain outside the Nix store.

## 2. Coordinator synthesis

- An on-demand Nix-owned user service, bound to loopback, with one synthesis
  admitted at a time and bounded requests.
- A persistent reference WAV plus exact transcript, restored into the engine's
  in-memory voice registry at startup. Missing references fail visibly.
- A relay command starts the service, waits for readiness and streams PCM.
  Disconnect and cancellation propagate to the engine.
- Warm service reuse during a reading session; release after idle.

## 3. Zenbook playback

- `speak` accepts text or a UTF-8 file and streams coordinator PCM over SSH
  into the client's selected PipeWire output. No inference on the laptop.
- Stop kills playback and upstream synthesis. Bound buffering and request
  sizes; serialize reading chunks without changing their words.
- Support calls from the coordinator by explicitly selecting the client.
- Exercise failure paths with fixtures, then copy built closures for a
  temporary end-to-end test before any fleet-wide activation.

## 4. Voice and acceptance

- Locate or extract clean K-2SO references from Tom's source. Preserve source,
  timestamps and exact transcripts; compare several short references.
- If those cannot produce a usable clone, render a similar original voice
  with Qwen VoiceDesign and enroll it into Base.
- Record warm/cold timing, first received audio, realtime factor, memory,
  chunk boundaries and stop/disconnect behavior. Distinguish transport timing
  from acoustically measured first audible sound.
- Deliver audition WAVs and a working client playback path. Long-form comfort
  and resemblance remain listening decisions for Tom.
- Tom's follow-up explicitly requests one VibeVoice comparison with the same
  K-2SO reference and audition text. Test its existing Large checkpoint in an
  isolated environment before selecting the final engine; keep the Qwen build
  as the implementation starting point.

## Completion evidence

Built both pinned Qwen Vulkan packages. The coordinator-to-Zenbook PCM route
works, including cancellation propagated to the generating engine. The relay
has eight passing behavior tests and a passing Nix topology check. Its service
starts on demand, restores the saved reference and releases weights after idle.
This is staged in the worktree, not merged or activated fleet-wide.

The source MP3 is preserved. The reference bank contains raw, light-cleaned
and Demucs-separated clips with exact transcripts, timestamps and hashes.
Qwen samples cover seven references and three original VoiceDesign fallbacks.
The legacy VibeVoice Large ROCm sample is also generated. Independent CPU
Parakeet checks flag text omissions/substitutions; they do not judge resemblance.

Full conversational wake/ASR orchestration and screen-selection OCR remain
subsequent work. The expanded ASR task below evaluates candidate inference;
it does not replace the working dictation route during this comparison.

## Expanded comparison requested during the build

1. Compare Serveurperso and Khimaros Qwen packages on identical text/reference
   with their own compatible weights/codecs. Preserve the liked baseline.
2. Test legacy VibeVoice Large, current C++ Realtime TTS and the C++ 1.5B
   raw-reference clone path. Do not describe a preset prompt as a new clone.
3. Test ordinary C++ VibeVoice ASR with speaker diarization and Microsoft's
   September 3 ASR-Streaming 1.5B release on the same synthetic A–B–A fixture.
   Separate actual live chunk processing from an offline file iterator.
4. Separate fresh-process loading, first delivered PCM, warm repeated synthesis,
   total RTF and long-passage completeness. Record process RSS, device GTT/VRAM,
   allocator peaks where exposed, and sampled APU PPT rather than wall power.
5. Document model lineage and exact source/model revisions. Qwen2.5 within
   VibeVoice is its trained speech backbone, independent of the assistant LLM
   and distinct from Qwen3-TTS. A new implementation is not a new checkpoint.
6. Deliver a local listening page with recordings and a measured report.
   No final model/voice selection has been made.

## Listening feedback

Tom liked the first Zenbook playback on September 14: Qwen 1.7B Base Q8_0,
Serveurperso Vulkan, raw intro9 reference (8.75 s). Preserve that exact
reference/profile as the comparison baseline; continue other engines before
selection. Proven route: coordinator → SSH → Zenbook PipeWire.
