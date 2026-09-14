# Existing voice-entry cue

The requested four Claude audio assets were found at
`/home/tom/colors/waves/capture/audio` on the coordinator (plural `colors`).
The preserved capture notes and filenames identify their events:

| Asset | Existing event | MP3 container duration |
| --- | --- | --- |
| `enter_voice_mode.mp3` | Enter voice mode | 0.601 s |
| `exit_voice_mode.mp3` | Exit voice mode | 0.967 s |
| `disconnected.mp3` | Disconnected | 0.731 s |
| `startup.mp3` | Imagine startup | 3.000 s |

`speech-listening-cue` plays the voice-entry asset. This mapping comes from the
existing name and capture record, not a guessed listening impression. The capture
notes attribute the three voice cues to `claude.ai/audio/voice/sfx/` and the
startup asset to an Internet Archive copy of `claude.ai/imagine/startup.mp3`.
Those are recorded origins, not a claim that the URLs were fetched again today.
All four original MP3 byte streams and SHA-256 hashes are preserved in `assets/`.

The Nix build verifies the selected MP3 hash and decodes it once into PCM16 WAV,
retaining the original sample rate, channels and gain. MPEG padding may make the
decoded playback duration differ from the container duration above. Runtime uses
one shell process followed by `exec pw-play`; FFmpeg is build-time only. The helper
uses the currently selected PipeWire output, accepts no arbitrary playback or
recording flags, and refuses playback on hosts other than `client`.

This package only plays a cue on explicit invocation. It creates no microphone
stream, background process, timer, wake detector or network connection. The built package is available in the laptop Nix store. The command has not
yet been activated in the user profile. This worktree now declares it in the
client-only Home Manager package list and exports `packages.x86_64-linux.speech-listening-cue`.
It is absent from the other hosts’ package lists; no service is added.

The future wake pipeline owns the conditions for calling it: only the explicitly
identified USB iContact webcam microphone is eligible; missing or changed device
identity must disable capture without a built-in microphone fallback. Call mode
must disable wake processing and its listening cue. Playback alone does not verify
that a microphone is ready. Those requirements belong to the future capture/state
controller, not to an always-running process in this package.
