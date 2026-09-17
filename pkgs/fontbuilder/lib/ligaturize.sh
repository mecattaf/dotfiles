#!/usr/bin/env bash
# fontbuilder stage S5 - ligaturize one face with its per-weight Fira donor.
#
#   ligaturize.sh <merged.ttf> <FiraCode-Weight.otf> <output-dir>
#
# --prefix "" is MANDATORY: Ligaturizer's default prefix is the literal "Liga"
# and it is applied ON TOP of --output-name, which gives "Liga Anthropic Mono"
# and blows the patcher's 31-char nameID ceiling once " Nerd Font Mono" lands.
# --output-name "Anthropic Mono" so the family the ligaturizer writes is the
# normalised one. Never --copy-character-glyphs (crashes on Python 3 at
# ligaturize.py:88 for this font, and would splice Fira's punctuation in).
#
# Ligaturizer does NOT create --output-dir: without it the whole run completes
# and then dies at font.generate() with a bare "OSError: Font generation
# failed". Hence the mkdir. Its output path is DERIVED, not chosen:
#   <output-dir>/<output-name without spaces>-<ID6 after the first hyphen>.ttf
# which is why S3's ID6 rule (exactly one hyphen, style with no spaces) is
# load-bearing for the driver's next input path.
#
# Ligaturizer is a FontForge script: its output carries a wall-clock FFTM and
# head.modified. S8 (canonicalize.py) runs on it before S6.
set -euo pipefail
src="$1"; donor="$2"; outdir="$3"
mkdir -p "$outdir"
cd "$outdir"
exec fontforge -lang=py -script "$FONTBUILDER_LIGATURIZER/ligaturize.py" \
  "$src" \
  --output-dir "$outdir" \
  --prefix "" \
  --output-name "Anthropic Mono" \
  --ligature-font-file "$donor"
