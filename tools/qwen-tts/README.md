# Local speech evaluation

This directory contains the evaluation harness and exact acquisition manifests.
In particular,
`qwen-serveurperso-cli` labels benchmark results for the upstream
[ServeurpersoCom/qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp)
CLI. The name comes from the repository owner.

The worktree packages two independent upstream Qwen implementations with their
matching model formats. The comparison also uses separately pinned VibeVoice
environments under `~/tts-audition-20260914/`. See that directory's `REPORT.md`,
`listening.html`, `vibevoice-cpp/README.md` and `vibevoice-asr/RESULTS.md` for
measured results, setup receipts and current limitations. The final synthesis is
also tracked in `docs/speech-evaluation-2026-09-14.md`. On the Zenbook, open
`~/Downloads/speech-review-20260914/listening.html` for the self-contained
comparison table and playable recordings.

## Reproduction

- `audition.py` renders the same text through raw/light/Demucs references and
  records exact arguments, hashes, output duration and process timing.
- `benchmark-cli.py` repeats fresh CLI processes, including reference encoding
  and loading. It does not claim resident-model warm timing.
- `benchmark-server.py` starts one fresh server and measures repeated requests
  with the same model resident. `--chunk-chars 400` exercises the relay's actual
  lossless chunker on the long passage. Existing disk/shader caches remain.
- `benchmark-lengths.py` tests bounded single-request prefixes through the guarded
  deployment service; independent transcript checks determine completeness.
- `measure.py` records sampled process RSS/CPU and AMD driver GTT/VRAM/busy/PPT.
  Counters overlap; PPT is not wall power. GPU inference jobs are serialized.
- `listening-page.py` embeds representative WAVs and the report in a portable
  HTML file. Repeated timing takes remain on disk, with receipts.

Each script exposes `--help`. Recorded JSON `argv`/`command` fields are the
authority for the actual tested binary, weights, seed and settings. Model files
are never fetched by inference. `manifests/` holds exact source revisions, sizes
and SHA256s for NAS acquisition and explicit coordinator loans.

## Qwen playback build

```bash
nix build .#qwentts .#qwen-speech
nix build .#checks.x86_64-linux.qwen-speech \
  .#checks.x86_64-linux.qwen-speech-topology
```

After the staged Nix configuration is activated and the three required model
files are explicitly loaned, enroll the tested reference on the coordinator:

```bash
qwen-speech enroll \
  ~/tts-audition-20260914/k2so/refs/intro_9s_raw.wav \
  ~/tts-audition-20260914/k2so/refs/intro_9s_raw.txt
```

On the Zenbook, `speak 'Your text'`, `speak --file passage.txt`, and
`speak --stop` use its selected PipeWire output. From the coordinator,
`speak --client client 'Your text'` forwards playback to the laptop.
`speak --output sample.wav 'Your text'` records locally instead. A failed render
is retained as `.part`, not passed off as a complete WAV.

The saved reference is restored whenever the service starts. Requests start
the loopback-only server, wait for its warmup, and serialize synthesis. After
five minutes idle it releases the model. A 100 ms host-memory guard refuses
startup or terminates only the speech engine below 16 GiB MemAvailable or at
64 GiB AMD device GTT. This is a reactive safeguard, not a GPU allocation quota;
missing counters fail closed. It complements the 400-character request chunks,
2048-token output cap and single-request admission limit. Stop/disconnect closes the upstream
stream and reaches the engine's cancellation callback. No model loads at boot.

During this comparison, built closures and a temporary runtime user unit proved
the route without merging the worktree or switching the fleet. The temporary
unit does not survive reboot. The listening HTML and recorded WAVs do.
