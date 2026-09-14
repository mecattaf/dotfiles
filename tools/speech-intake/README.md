# Coordinator audio intake experiments

All inference runs on `coordinator`. NAS `library-fetch` acquires canonical
weights; `local-models-borrow` copies and verifies them. Never download model
weights directly onto the coordinator or client. The manifest in `manifests/`
adds the audio projector and E4B artifacts; 12B Q8 already exists in the Library.

Reproduce with the saved fixture manifest (absolute WAV paths, expected words,
duration and SHA256) under `~/tts-intake-gemma-20260914/fixtures/manifest.json`:

```sh
python3 tools/speech-intake/benchmark.py --model 12b --root ~/tts-intake-gemma-20260914
python3 tools/speech-intake/benchmark.py --model e4b --root ~/tts-intake-gemma-20260914
python3 tools/speech-intake/benchmark.py --model 12b --user-asr --root ~/tts-intake-gemma-20260914
python3 tools/speech-intake/benchmark.py --model 12b --english-asr --root ~/tts-intake-gemma-20260914
```

Run serially, with Qwen idle. The runner starts a loopback-only ROCm llama-server
using explicit local model/projector paths. No microphone, playback, or agent
actions occur. It enforces coordinator hostname, a 16 GiB MemAvailable floor and
64 GiB system AMD GTT ceiling. The server exits after the suite. Existing result
paths are overwritten on a repeat; archive results before rerunning.

The original suite uses a short system instruction and generic user audio text.
`--user-asr` is a separate diagnostic that puts a shorter transcription instruction
in the user message beside the audio. It changes both wording and placement;
any improvement cannot be attributed to either variable alone.

Measurements are saved-audio HTTP request times, not live endpoint latency.
First text and complete response times are separate. Temperature 0, seed 42,
thinking disabled; no MTP. Dense context is a synthetic inactive catalog of
approximately 23k input tokens, not a real agent tool/history prompt. Only one
routing utterance is tested. Most speech fixtures are synthesized, one is an
actor excerpt; this is not a validation on Tom's voice, French or room noise.

WER lowercases and removes punctuation but treats K-2SO and K2SO differently.
Read raw output alongside edit counts; extra translations and duplicate words
are retained as failures, not silently stripped. Markdown fences around routing
JSON are tolerated by the evaluator, not proof of strict schema adherence.

RSS and GTT are different measurements with overlapping shared allocations;
do not add them together. GTT is system-wide, not exclusive model memory.

`--english-asr` uses explicit English-to-English ASR wording beside the audio.
It fixed unsolicited translation/duplication on this saved English suite, including
empty silence. It is not an automatic language-detection or code-switching solution.
