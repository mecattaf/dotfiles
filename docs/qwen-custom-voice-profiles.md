> Historical investigation, retired from the active plan by Tom on 14 September 2026. The selected direction is Qwen Base with one broad-source K2SO voice; no character personality or alternate-tone profiles.

# Prepared CustomVoice profiles

The wrapper supports a prepared CustomVoice model alongside the existing Base reference profile. This is setup-time model selection: normal requests select an embedded speaker, without extracting reference audio, computing speaker embeddings, or training. Installing a profile is explicit; adding this support does not change the live `voice.json`.

The existing Base profile continues to use the service’s `--model` and `--codec` paths and enroll `assistant-main` on engine startup. A version 1 CustomVoice profile overrides those paths with already-loaned GGUF files, checks their size/header, and checks the loaded server’s built-in speaker inventory. CustomVoice performs no reference-enrollment POST. The common memory guard, on-demand lifecycle, 400-character lossless partitioning, PCM transport, and atomic WAV publication remain in effect.

The current `dry`, `reassuring`, and `urgent` names are historical experiment IDs. They do not establish observed emotion in a source recording or a final production palette. Tom requested an independent acoustic pass before selecting the final variants; personality remains a separate draft.

## Profile format

All fields below are required. Replace the example paths, hashes, byte counts, and placeholder `take_b` mapping with the prepared artifacts’ actual values. `allowed_speakers` contains `k2so_primary` and at most four other explicitly prepared `k2so_*` IDs. The default is always `k2so_primary`; every listed ID must be present in the loaded model's speaker inventory.

Tone IDs are defined by each profile, with `neutral` required and at most four optional alternatives. Tone and speaker IDs are at most 32 characters: start with a lowercase ASCII letter, then use lowercase letters or digits separated by single underscores. Spaces, hyphens, leading/trailing or repeated underscores, shell punctuation, and duplicate speakers are rejected. These limits constrain configuration and transport; they do not prescribe acoustic or personality categories. Existing version 1 profiles using `dry`, `reassuring`, or `urgent` remain valid.

```json
{
  "version": 1,
  "mode": "custom_voice",
  "name": "assistant-main",
  "model": "/var/lib/local-models/PREPARED-MODEL/talker.gguf",
  "model_sha256": "REPLACE_WITH_64_LOWERCASE_HEX_DIGITS",
  "model_bytes": 0,
  "codec": "/var/lib/local-models/PREPARED-CODEC/tokenizer.gguf",
  "codec_sha256": "REPLACE_WITH_64_LOWERCASE_HEX_DIGITS",
  "codec_bytes": 0,
  "allowed_speakers": ["k2so_primary", "k2so_take_b"],
  "default_speaker": "k2so_primary",
  "instructions": "",
  "tones": {
    "neutral": {
      "speaker": "k2so_primary",
      "instructions": ""
    },
    "take_b": {
      "speaker": "k2so_take_b",
      "instructions": ""
    }
  },
  "settings": {"temperature": 0.9}
}
```

`neutral` must exactly match the default speaker and instructions. Other tones are optional and must select an allowed speaker; multiple tones may use the same speaker with different reviewed instruction strings. No alternative names are built into the wrapper. Empty instructions in the example make no delivery request; configure instructions explicitly after separate acoustic and transfer evaluation. An unavailable category should remain absent instead of silently falling back. Unknown profile fields, unsafe IDs, unlisted speakers, and requested tones absent from the loaded profile are rejected.

Instructions are limited to 2,048 UTF-8 bytes each, without NUL bytes; an empty string is allowed. Sampling overrides accept `seed`, `temperature`, `top_k`, `top_p`, `repetition_penalty`, and the three `subtalker_*` equivalents. Values are bounded and checked for type and finiteness. Output token limits remain controlled by the wrapper: 2,048 for speech, 120 for warmup. `speed` and arbitrary API fields are not accepted settings.

## Explicit installation and use

After reviewing the candidate and loaning its weights through the existing Library workflow, install it **on the coordinator**:

```sh
qwen-speech use-custom-voice --profile /absolute/path/prepared-voice.json
```

The command validates both artifacts’ full SHA256 hashes once, acquires the synthesis lock, stops the speech service, saves the previous profile byte-for-byte as a unique `voice-backup-*.json` in the state directory, and atomically installs the new profile with mode 0600. It neither downloads weights nor starts inference. A bad hash is rejected before stopping the service or changing the profile. State defaults to `~/.local/state/qwen-speech`; `QWEN_SPEECH_STATE` can select an isolated test state.

Subsequent requests check file existence, GGUF headers, and expected sizes, without hashing gigabytes daily. Startup requires every declared speaker to appear with `kind: speaker` in the server inventory; a dynamically registered clone does not satisfy that check. Warmup uses the prepared default speaker and instructions. The inventory contract comes from the [pinned runtime HTTP implementation](https://github.com/ServeurpersoCom/qwentts.cpp/blob/71ad93d591a2811f35db77e27c02acba091c9e9b/src/tts-server.h).

```sh
speak --tone take_b "The selected recording is ready, Tom."
speak --client client --tone take_b "The microphone settings are ready, Tom."
speak --tone neutral --file reading.txt --output reading.wav
```

Omitting `--tone` uses the profile default, equivalent to its `neutral` entry. The CLI checks ID syntax before SSH forwarding; the coordinator checks membership against its installed profile before starting synthesis. Client machines do not need a copy of that profile. Tone selection travels safely through both SSH hops. The speaker is sent in HTTP `voice`; instructions go in HTTP `instructions`, separately from the unchanged `input` text. There is no bracket parsing, inserted actor direction, automatic tone inference, or document rewriting. Base profiles reject `--tone` explicitly.

## Rollback and validation boundary

To return to Base, stop speech and restore the exact saved Base `voice-backup-*.json` to `voice.json` while no reading is active, retaining private file permissions and an atomic rename. The service’s original Base model/codec arguments then apply again. Alternatively, explicit `enroll WAV TRANSCRIPT` installs a validated Base reference through its existing path. Keep the liked baseline backup; profile installation does not delete backups or loaned weights.

Unit tests cover legacy Base and CustomVoice profiles, profile-defined IDs and bounds, separate instruction/text handling, rejection before service start, dynamic speaker-inventory checks, prepared path selection, install-time hashing and backups, both SSH tone hops, and preservation of a previous successful WAV when synthesis fails. They do not establish voice resemblance, instruction quality, GPU compatibility, or successful fleet activation; those require the prepared-model audition and deployment checks.
