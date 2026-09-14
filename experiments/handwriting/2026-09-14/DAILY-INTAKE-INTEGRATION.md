# Manual daily intake integration

The new implementation lives in `~/mecattaf/dotfiles/pkgs/handwriting-intake/`. Its README is the command contract and limitations; the package includes its offline tests. This note records the handoff to the dotfiles integration, not activation or a completed real-page trial.

The package wraps `intake.py` with default state `/var/lib/handwriting-intake`; explicit `--state` still overrides it. Root integration owns the package registration, the Tom-owned0700 state directory and managed NAS backup. No consumer/scanning/inference service or timer is added by the package.

Use the new real Huion batch explicitly:

1. `handwriting-intake receive /home/tom/Paper/inbox/BATCH/pageN-DD-MM.json`
2. Inspect the durable receipt; legacy completeness stays unknown.
3. `handwriting-intake run CAPTURE_ID --allow-unknown`
4. Import the returned packet: `handwriting-annotation --state /var/lib/handwriting-annotation import-items --items PACKET`
5. The writer reviews the complete capture at `handwriting.internal`, separately from individual doubts.
6. `handwriting-intake export CAPTURE_ID --review-state /var/lib/handwriting-annotation --output-dir /home/tom/Paper/transcribed`

The consumer never promotes model-review events to writer approval, never writes the print intake, and never deletes received originals. Finalization means an explicitly reviewed capture transcription, not a claim that the physical device page was completely captured. Per-revision publication keeps literal Markdown separate from provenance and the complete related correction history as of that export.

`handwriting-intake snapshot --output NEW_VERSION_DIR` waits for the global `intake.lock`, uses SQLite.backup, retains objects/attempts/receipts plus tracked external export bytes, and writes a complete checksum manifest last. Existing destinations are refused. Restore to the same state path for direct continuation, because historical review/request evidence preserves absolute original paths. No pruning or NAS transfer is implemented inside this package.

Validation completed without GPU calls:12 offline tests pass. A separate temporary-state contract smoke used one existing real Huion JSON/SVG/PNG group with an explicitly unrelated saved-response fixture solely to exercise wiring. It imported the resulting whole-page and uncertainty tasks twice through the actual annotation backend without duplicates, remapped parent links correctly, and created zero writer events. That smoke is not OCR evidence and did not modify live state.

The renderer preserves deployed thin-stroke geometry and orientation but uses a versioned fivefold Pillow rasterization, not a claim of bitwise ImageMagick equivalence. The next actual page trial must validate the rendering and reading. Source completeness receipts, physical-page family reconciliation, automatic dispatch, the first14-day marker/audit schedule and safe writer-example consumption remain outstanding. Examples are deliberately absent while the target family's boundary is unknown.
