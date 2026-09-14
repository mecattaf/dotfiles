# Handwriting experiment source archive — 2026-09-14

This preserves the experimental source and methodology from `~/huion` in the
canonical dotfiles checkout. It is a historical source archive, not an installed
CLI, a production service, a portable dataset bundle, or a claim that real-Huion
commissioning is complete. The original scripts are copied byte-for-byte; their
workspace paths, data expectations and historical notes have not been rewritten.

`source-manifest.json` records the original absolute path, archive-relative path,
SHA256, size and original mode for each of the 53 copied files (446,514 bytes).
This README and the manifest are archive metadata, not copies of source files.

## Contents

- `ocr/`: eight Python scripts/tests and seven methodology documents from the
  initial small-Huion experiments, context-hint prototype and memory audit.
- `journal-photos/2026-09-14/experiment/`: all 18 Python experiment scripts/tests,
  including preprocessing, serial benchmarking, uncertainty audits, frozen
  correction selection, page reconstruction, scoring and tile probes.
- `journal-photos/2026-09-14/*.md`: eight methodological/status documents,
  including the final dated REPORT and WORK-STATE checkpoint.
- `journal-photos/2026-09-14/runs/writer-confirmation-off/compare.py`: the offline
  source that compares the latest 17-photo confirmation with the earlier pass.

The latest pass completed all 17 calls in 406.51 seconds with thinking explicitly
off. Every answer matched the previous pass byte-for-byte. The dated report also
records targeted writer adjudications and the completed 107-item model-review
import (zero pending review tasks). Real Huion commissioning remains pending
at that particular snapshot. These historical
statuses can become stale; use the canonical operations docs for current state.

Additional preserved sources include the historical Bluetooth/capture helpers
under `artifacts/scripts/`, the exact writer/model reconciliation scripts, and
root commissioning/handoff documents. These are archived source, not installed
services or current instructions to restart Bluetooth or change the fleet.

## Data and runtime boundaries

Photos, generated transcripts, frozen reference readings, original requests and
responses, timing/memory streams, notebooks, databases and machine-local secrets
are not copied into Git here. Full workbench and notebook evidence are archived
separately on the NAS; consult the final archive receipt in the canonical intake
documentation for the verified location. Relative links to those omitted files
remain references to the original workbench layout, not standalone archive links.

The scripts still require the original `/home/tom/huion` workspace layout and
its inputs (or a deliberately restored equivalent), Python and Pillow. Some
entrypoints contact the worker, sample memory over SSH, or write experiment
outputs when run. They are retained for reproducibility, not auto-executed by
Nix or imported as a production pipeline. Do not change the resident model or
copy historical engine plans into service configuration to run this archive.

The live accumulation mechanism is separate: the annotation service preserves
append-only review events and evidence under `/var/lib/handwriting-annotation`.
Writer decisions and model-assisted reviews retain distinct provenance; model
agreement does not create writer-approved training examples. Its consistent
daily snapshots are under `/mnt/nas/documents/handwriting-annotation-backups`.
See [intake operations](../../../docs/handwriting-intake.md) and
[annotation operations](../../../docs/handwriting-annotation.md).

## Archive verification

All 53 copied files were compared byte-for-byte with their source paths and
verified against the SHA256 manifest. All 30 Python files passed syntax parsing.
The archived initial OCR suite passed all three tests. The journal suite passed
all 41 tests in the original workspace, without inference calls.

Running that same journal suite inside this source-only archive passes 39 tests
and reports two missing-data errors: the frozen-reference assembly check and
the stale-completion cleanup check require the deliberately omitted
`codex-reviewed/` fixture. This is a documented data dependency, not an archived
claim that every test runs without the evidence bundle. No source paths or test
expectations were modified to conceal it.

To verify the archived bytes without accessing the worker:

```sh
python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path('experiments/handwriting/2026-09-14')
manifest = json.loads((root / 'source-manifest.json').read_text())
for item in manifest['files']:
    raw = (root / item['archive_path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == item['sha256'], item['archive_path']
print(f"Verified {len(manifest['files'])} archived files")
PY
```
