#!/usr/bin/env bash
# fontbuilder stage S7 - nerd-font-patcher, LAST.
#
#   nerdpatch.sh <aligned.ttf> <output-dir> <log-file>
#
# LAST because it is the only stage that validates and rewrites the whole name
# table (31-char nameID1/16 ceiling, nameID16/17, the NFM abbreviation, the
# conventional filename, ";Nerd Fonts <patcher version>" in nameID5). It is explicitly
# ligature-aware (set_sourcefont_glyph_widths skips glyphs already at cell
# width: "Ligatures will have these"), so it cannot flatten S5's negative
# bearings; measured 136/136 calt lookups survive.
#
# The patcher on PATH is pkgs/fontbuilder/nerd-font-patcher.nix, an
# overrideAttrs that lands glyphnames.json in $out/bin (the nixpkgs wrapper
# rewrites sys.argv[0] before fetch_glyphnames() reads its dirname, so a shim
# directory can never work). Without it icons keep raw names (uniE0B0 instead
# of pl-left_hard_divider); with it, +35 KB of post table per face.
#
# THE GATE IS THE LOG GREP, NEVER THE EXIT CODE: a family two characters too
# long yields three ^ERROR lines about over-length names and exit 0.
#
# FLAGS THAT MUST NEVER BE PASSED, each with its measured reason:
#   --cell '?'          does NOT query; it runs the full patch into $PWD (how a
#                       440 KB TTF once landed in the repo root)
#   --careful           keeps the PUA but stops the cell-filling box/block art
#                       (U+2588 -> (-50,0,1250,1440) instead of the full cell)
#   --pomicons etc.     naming sets instead of --complete makes nameID16 183
#                       chars ("... Plus Font Awesome Plus ...") with ERRORs;
#                       the Pomicons overwrite of U+E001-E00A is undone by S7b
#   --adjust-line-height no-op here (1985+515 is even) and confusing
#   --removeligs        inert without --configfile; never ask for it
#   --makegroups 1      folds the weight into nameID1 and overflows 31 chars
#                       for Light/Medium/SemiBold/ExtraBold; 4 is what official
#                       Nerd Fonts 3.x releases use
set -euo pipefail
src="$1"; outdir="$2"; log="$3"
mkdir -p "$outdir"
cd "$outdir"
nerd-font-patcher --complete --mono --makegroups 4 --outputdir "$outdir" "$src" >"$log" 2>&1 || {
  echo "nerdpatch: patcher exited non-zero, see $log" >&2; exit 1; }
if grep -qE '^ERROR|^CRITICAL' "$log"; then
  echo "nerdpatch: ERROR/CRITICAL lines in $log:" >&2
  grep -E '^ERROR|^CRITICAL' "$log" >&2
  exit 1
fi
