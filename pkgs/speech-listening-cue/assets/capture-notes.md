# Claude's sounds — captured

Four audio assets. All fetched from Anthropic-controlled origins; both origins verified by
trying the alternatives (`assets.claude.ai` and `assets-proxy.anthropic.com` both 404 for the
voice SFX — only `claude.ai` serves them).

| file | source | duration | channels | notes measured |
|---|---|---|---|---|
| `startup.mp3` | `claude.ai/imagine/startup.mp3` *(via Internet Archive — site is dead)* | **3.00 s** | mono | **C3 E3 G3 C4 G4 E5** — a C major triad across four octaves |
| `enter_voice_mode.mp3` | `claude.ai/audio/voice/sfx/` *(live)* | 0.60 s | stereo | A5 → A#5 → B5 → C6 — **rising** |
| `exit_voice_mode.mp3` | `claude.ai/audio/voice/sfx/` *(live)* | 0.97 s | stereo | E5 → F5 → F#5 → G5 |
| `disconnected.mp3` | `claude.ai/audio/voice/sfx/` *(live)* | 0.73 s | stereo | B4 → C5 → C#5 → D5 |

## What the analysis shows

**`startup.mp3`** is the outlier and the centrepiece: three full seconds, mono, a warm
open-voiced **C major** chord struck once and left to decay (envelope 0.25 → 0.29 → 0.06).
Spectral centroid 364 Hz — low and warm. C major, open voicing, no embellishment: the most
unfussy possible "welcome". Its ID3 encoder tag is `Lavf60.16.100`, so the shipped file was
transcoded with ffmpeg from an earlier master.

**The three voice SFX** are a consistent family, clearly designed together: all sub-second,
all stereo, all sharply decaying, and all built from *narrow chromatic clusters* rather than
chords — a few semitones packed close, which reads as a soft "blip" rather than a musical
statement. They sit progressively higher as the action gets more affirmative:

- `disconnected` centroid **615 Hz** (lowest, B4–D5)
- `exit_voice_mode` centroid **791 Hz** (E5–G5)
- `enter_voice_mode` centroid **1014 Hz** (highest, A5–C6)

So entering voice mode is the brightest and highest, disconnecting the darkest and lowest —
pitch height tracks the valence of the event. That is a deliberate design, not a coincidence.

## Playback

```sh
mpv --no-video ~/colors/waves/capture/audio/startup.mp3
```

## Note

`startup.mp3` exists only because it was pulled from the Internet Archive before
`claude.ai/imagine` went dark — it is not obtainable from the live web. The three voice SFX
are currently still served live.
