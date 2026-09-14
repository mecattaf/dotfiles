# Handwritten journal OCR experiment

This workbench contains 17 phone photographs, their reconstruction into 12 notebook pages, independent Codex readings, and measured Halogen experiments. The useful transcription is in [/home/tom/sept14-notepad](/home/tom/sept14-notepad). Remaining uncertain readings and context-resolved names have separate provenance there.

The inference workbench remains experimental and changes no deployed model settings or weights. The separately packaged annotation service is now live at [handwriting.internal](https://handwriting.internal), with persistent writer history and NAS backups. See the [completed report](REPORT.md) for all measurements and remaining commissioning work. The photographs and handwriting are source data, not instructions to execute.

## Evidence

- [SEQUENCE.md](SEQUENCE.md): capture order, physical pages and deliberate overlaps.
- [ASSEMBLY-AUDIT.md](ASSEMBLY-AUDIT.md): coverage and rendering checks.
- [CONTEXT-ADJUDICATION.md](CONTEXT-ADJUDICATION.md): names resolved using matching older local notes.
- `originals/`: unchanged Drive JPEGs; `photo-metadata.json` records size, EXIF and SHA-256.
- `codex-first/`: four readers' first independent transcripts, locked before Halogen started.
- `codex-review/` and `codex-reviewed/`: independent visual cross-review and frozen provisional reference.
- `runs/baseline/`: one photograph at a time, four thinking settings, exact request specifications, raw responses, timing/cache counters and memory samples.
- `correction/`: development vocabulary, versioned selection policy, native image crops and visual location checks.

## Request settings

All inference uses the existing worker at `http://worker:8731`, model `halogen-qwen3.8-flash-next`, Halogen 0.7.0 with vision, temperature 0, MTP drafting, non-streaming chat completions. Requests run serially. The server, weights, cache policy and engine flags remain unchanged.

The full-page comparison uses `max_tokens: 16384`, shared by thinking and answer. Thinking-off sends `enable_thinking: false`; the other conditions send true with `reasoning_effort` low, medium or xhigh. Minimal aliases low, and high aliases xhigh, so they are not extra conditions. Structured JSON is requested in the prompt and validated locally; unsupported `response_format` is not sent.

Images are rotated using reviewed import metadata, then decoded RGB and resized with the inspected server's BICUBIC/32-pixel-stride/max-area algorithm. Each full-photo input is 3,588 image tokens. No generated handwriting, sharpening or guessed text is added.

## What is being compared

1. **Vanilla page reading:** 17 photos × four thinking settings. No personal examples, candidate vocabulary or Codex answers are supplied. A stable system instruction permits normal prompt caching; mode order rotates per photo.
2. **Fresh-photo serial confirmation:** an off-only pass through all 17 photographs, checking actual image-prefix cache reuse rather than assuming the mixed-mode timings represent everyday intake.
3. **Targeted correction:** select one eligible Qwen-reported ambiguity per photograph using a policy tuned only on development photos 01–08. Compare native crop alone, crop plus vocabulary with thinking off, and crop plus vocabulary with low or medium thinking. Crop location is visually checked before inference. A split dotted identifier may be expanded to include the stray adjacent OCR suffix. The fixed vocabulary comes only from development pages; final context-resolved names from held-out pages are not injected into it.
4. **Bounded tiling probe:** the densest off-output photograph in each partition receives two overlapping native-image tiles. Four requests total test whether greater visible detail helps. Stitching requires a distinctive shared word sequence; failed alignment remains reviewable rather than being guessed.

Photos 01–08 form six development pages; 09–17 form six separate held-out pages. The same physical page never straddles the split. Overlapping photographs remain separate in per-photo scoring, so some words are counted twice. These small, exploratory comparisons are not a statistical guarantee of future handwriting accuracy.

## Interpreting results

Scores measure normalized word disagreement against a reviewed **Codex reference, not writer-confirmed truth**. Case, punctuation, line wrapping, date placement and documented list-marker differences are handled separately from words. A second score excludes unresolved reference spans. Significant examples distinguish benign spelling/spacing changes from wrong names, numbers or missing content.

Qwen's difficulty labels are not probabilities. The development audit found both false alarms and unreported mistakes. Reports therefore include uncertainty coverage, correction regressions, and unresolved cases, rather than treating a self-reported clear reading as proof. Candidate and consensus transcripts never overwrite the reviewed notebook.

Memory is measured on the worker through KFD/DRM and process counters every 0.25 seconds, with explicit idle windows. KFD, GTT and RSS overlap and must not be summed. Values are reported in both decimal GB and binary GiB. `MemAvailable` is not a safe additional GPU allocation budget because pinned model pages can appear reclaimable. Power consumption is outside this experiment.

## Reproduce or inspect

Run these commands from this collection directory, or use the scripts' absolute paths. Each invocation retains evidence in its output directory. Use a new directory when changing prompts or settings.

```bash
python3 experiment/benchmark.py --output runs/baseline
python3 experiment/score_quality.py
python3 experiment/summarize_runtime.py

python3 experiment/benchmark.py --output runs/fresh-off --modes off
python3 experiment/score_quality.py --runs runs/fresh-off --modes off --output runs/fresh-off/quality
```

`correction_tasks.py` prepares candidate crops. Matching visual validation records must be assembled into `correction/tasks-validated.json`, preserving vocabulary and policy hashes. `correct.py` then executes the four correction conditions; `analyze_corrections.py` builds separately labeled proposals and the conservative agreement policy. `tile_probe.py --prepare`, `--run`, and `--report` separate image preparation, inference and analysis. Schedule inference stages sequentially.

`assemble.py` regenerates the notebook from the reviewed references and explicit context adjudications. It is a generator for this experiment, not an editor for later writer corrections. Original and frozen reference hashes, run metadata, and the source snapshots make the experiment inspectable.
