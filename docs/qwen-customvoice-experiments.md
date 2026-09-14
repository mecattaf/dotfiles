> Historical investigation, retired from the active plan by Tom on 14 September 2026. The selected direction is Qwen Base with one broad-source K2SO voice; no character personality or alternate-tone profiles.

# Qwen CustomVoice: prepared identity and independent delivery controls

Qwen remains the selected TTS family. The liked Base 1.7B Q8 recordings are preserved listening references; an expressive replacement is being evaluated through the same qwentts.cpp Vulkan engine on the coordinator. The personality proposal is **not final** and belongs to a separate pass. It does not define the acoustic palette.

## What was built

Community work from [gabriele-mastrapasqua/qwen3-tts](https://github.com/gabriele-mastrapasqua/qwen3-tts/tree/e56ec7e6eabbed608b13bfbd3fba431708b2077f) informed an offline GGUF transplant. This retains the already-tested [qwentts.cpp runtime](https://github.com/ServeurpersoCom/qwentts.cpp/tree/71ad93d591a2811f35db77e27c02acba091c9e9b) and Vulkan backend rather than introducing another inference server. Source repositories and conversion scripts are retained under `/home/tom/tts-expressive-candidates`. A portable copy of the exporter is tracked as [`export-customvoice-graft.py`](../tools/qwen-tts/export-customvoice-graft.py); supply the pinned `gguf-py` checkout through `PYTHONPATH` with NumPy and PyYAML available. Explicit derivative borrow manifests are in `tools/qwen-tts/manifests/k2so-customvoice-*.json`. No weights are stored in Git.

Three local derivatives are archived on the NAS and explicitly borrowed onto the coordinator:

- **X-vector transplant:** CustomVoice Q8 backbone with four normalized reference-derived speaker vectors in an F32 codec embedding table.
- **Fuller graft:** preserves the CustomVoice transformer/code predictor, substitutes Base input projections and the first 2,048 acoustic codec rows, and preserves exact Base special text embeddings for IDs 151671–151673. CustomVoice control/speaker rows remain intact except for four explicit speaker replacements. This is mixed Q8/BF16/F32 precision, not a pure Q8 file.
- **Full-library primary:** changes only the fuller graft's primary speaker row, using an embedding extracted from the 73.35-second curated bank. The other three speaker rows and all other bytes are unchanged; prefix/suffix checks and byte comparison verify that boundary.

These are experimental prepared models. They are not fine-tunes on emotionally labeled examples, and they do not contain a learned catalog of the source scenes. The original four IDs (`k2so_primary`, `k2so_dry`, `k2so_reassuring`, `k2so_urgent`) identify reproducible experiments, not final emotion classes.

## What the full reference library means

The supplied montage lasts 175.705 seconds. Thirteen selected passages cover 71.91 seconds of original audio; twelve 120 ms artificial joins produce the 73.35-second bank. No speech was accelerated, and no internal phrase audio was removed. The full montage has not received an exhaustive speaker-isolation audit. Music, effects, close neighboring-speaker boundaries, and a few unresolved transcript words remain recorded limitations.

The speaker encoder pools the bank into one 2,048-value representation. That combines source information but does not retain separately addressable timing, pitch contours, or thirteen emotional states. Prosody and recording conditions may influence this vector; it is not guaranteed to encode identity alone. Individual passages remain available for separate comparisons.

Source annotations distinguish scene meaning from vocal evidence. “Apology,” “question,” and “directive” describe the words. They do not prove an embarrassed, skeptical, or urgent sound. The independent acoustic inventory records complete-clip transcript density and recording levels, while withholding unreliable pitch and pause estimates from the mixed soundtrack.

## Completed short comparisons

The preset control has four takes. Both the x-vector and fuller graft variants have ten takes. The full-library primary has four takes. All 28 completed takes passed independent CPU transcription checks with zero normalized word edits on the same 35-word text. Resident generation was approximately RTF 0.24 on the Radeon 8060S. No output caps or new kernel records occurred in these measured windows. Wording checks do not establish perceived identity or expressive quality.

A second experiment holds the fuller graft's primary identity and the same text fixed while requesting five acoustic deliveries: steady, measured, brisk, wider pitch variation, and soft. Two seeds provide ten takes. All ten passed wording checks, with durations 10.88–13.20 seconds and RTF 0.242–0.244. These are requested conditions, not measured achievements: the measured-pacing instruction produced shorter readings than steady in both seeds. Reliable control of the requested acoustic dimensions remains a listening and measurement question.

An uncalibrated same-family embedding comparison favors the fuller graft over the other two new primary candidates against the selected anchors. It is a diagnostic proxy, not a perceptual ranking or a basis for declaring a final winner. The liked Base anchor also differs in text and duration from the short candidates.

## Daily operation and selection boundary

Model preparation, source curation, and speaker extraction happen during setup. A prepared CustomVoice request supplies an embedded speaker ID, ordinary text, and a separate delivery instruction. It does not reprocess the reference library or train a model. No bracketed stage directions are inserted into the spoken text. [Prepared profile documentation](qwen-custom-voice-profiles.md) describes the installation and rollback mechanism.

The final palette remains one dominant identity and at most four useful alternatives. Select them by transfer quality, identity continuity, intelligibility, and stitching behavior, independently of the future personality pass. Do not create extra presets merely to fill those slots.

The saved live profile remains the liked Base reference during these comparisons. The new wrapper and models are built, but this worktree has not been merged into the raw dotfiles checkout or activated fleet-wide. Derived NAS artifacts currently have explicit local borrow manifests and provenance; they are not misrepresented as upstream Hugging Face files in the catalog.

## Review artifacts

- Portable listening page: `/home/tom/Downloads/tts-reference-refinement-20260914/expressive.html` on the Zenbook, containing all 38 short auditions, four long CustomVoice recordings, and the two spoken explanations.
- Earlier reference matrix: adjacent `listening.html`, containing 17 reference combinations and 41 generated outputs, including failed long-reference examples.
- Detailed experiment roots: `/home/tom/tts-expressive-candidates/qwen-customvoice` and `/home/tom/tts-reference-refinement-20260914` on the coordinator.
- The requested six-minute explanation uses the liked Base voice: 359.44 seconds of audio generated in 87.23 seconds, with 19 deterministic text chunks joined into one WAV. It is not presented as a final CustomVoice demonstration.

All timings retain their scope. Short resident tests exclude model load and client playback; the spoken explanation's timing includes synthesis transport backpressure. The matched long comparisons are now complete: the fuller graft produced 146.32 seconds in 35.43 seconds from seven chunks, and a 94.08-second one-shot in 23.49 seconds. The full-library primary produced 140.80 seconds in 34.06 seconds from seven chunks, and an 89.92-second one-shot in 22.43 seconds. No generation reached its output cap and neither measured window recorded new kernel events. The full-library stitched reading had zero edits across 344 normalized words; the graft had one article disagreement. The 228-word one-shots each had two strict transcription edits involving word segmentation or phonetic ambiguity. These 1,466-character one-shots are the longest continuous CustomVoice cases tested here, not demonstrated hard model limits. Keep the deterministic 400-character policy while collecting broader length evidence.
