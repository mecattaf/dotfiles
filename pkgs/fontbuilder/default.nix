# fontbuilder — the press that produced nas:/mnt/fast/fonts/anthropic/*.tar.zst.
#
# It ships the RECIPE and NO FONT BYTES. `src` is scripts and JSON only: the
# derivation builds, and its checkPhase passes, on a machine that has never
# seen ~/colors, so `nixos-rebuild switch` on the worker never needs the
# capture tree. Stage S0 checks the capture tree against data/sources.sha256
# and exits 2 with "fontbuilder: source tree does not match the pinned
# digests" otherwise.
#
#   nix run .#fontbuilder -- /home/tom/colors/waves/capture ~/build/anthropic-fonts
#
# See ./README.md for the stage table, the flags that must never be passed, and
# the reproducibility argument. kitty (for the resolver tests) and fc-* come
# from the host PATH on purpose: the tests must exercise the SAME kitty and
# fontconfig the desktop runs.
{
  lib,
  stdenv,
  callPackage,
  writeShellApplication,
  shellcheck-minimal,
  fetchFromGitHub,
  python3,
  fontforge,
  harfbuzz,
  pango,
  imagemagick,
  util-linux,
  zstd,
  gnutar,
  coreutils,
  jq,
  nerd-fonts,
  dejavu_fonts,
  maple-mono,
}:

let
  py = python3.withPackages (ps: [
    ps.fonttools
    ps.brotli
    ps.zopfli
  ]);

  # Ligaturizer is pinned by rev, not taken from nixpkgs: the ligature glyph
  # numbering (lig.1 … lig.136) that stage S6 re-seats is an implementation
  # detail of THIS revision.
  ligaturizer = fetchFromGitHub {
    owner = "ToxicFrog";
    repo = "Ligaturizer";
    rev = "c4065187a544a8fab40826fc91db1c6180a2d342";
    hash = "sha256-89/6xEBybIG9OfeOkwh8bwvQpp8+SOCbUxIlqbdkvqU=";
  };

  # The EXACT rev of Ligaturizer's fonts/fira submodule (Fira Code 3.001).
  # nixpkgs' fira-code 6.2 is NOT a substitute: measured, it ships only
  # FiraCode-VF.ttf and 53 of the 138 wanted `*.liga` glyph names are absent
  # after the 6.x rename. Fetched separately because fetchFromGitHub does not
  # fetch submodules and the other four (Montserrat, codeface, plex, spacemono)
  # are dead weight.
  firaCode = fetchFromGitHub {
    owner = "tonsky";
    repo = "FiraCode";
    rev = "e9943d2d631a4558613d7a77c58ed1d3cb790992";
    hash = "sha256-rMhI9B3QR4IzJNukqoq7iRFIdrfEwMBD/UsNeNq4Q88=";
  };

  # The patcher with glyphnames.json in its own bin/ (see that file for why a
  # shim directory cannot work).
  patcher = callPackage ./nerd-font-patcher.nix { };

  # MEASURED 2026-09-17: nixpkgs' nerd-fonts.jetbrains-mono installs 96 files
  # into share/fonts/truetype/NerdFonts/JetBrainsMono/ (six variants). The
  # merge takes the MONO cut, JetBrainsMonoNerdFontMono-<Style>.ttf, whose
  # cell is 600/1000 upm = 0.600 em, exactly the Anthropic 1200/2000 cell.
  jbmDir = "${nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";
in
writeShellApplication {
  name = "fontbuilder";

  runtimeInputs = [
    py
    fontforge
    patcher
    harfbuzz.dev # hb-shape lives in the dev output; hb-view exists in NEITHER harfbuzz nor harfbuzzFull
    pango # pango-view: the specimen rasteriser (real fontconfig+HarfBuzz+FreeType stack)
    imagemagick # composites the per-style specimen sheets
    util-linux # `script`, a tty for `kitty +runpy`
    zstd
    gnutar
    coreutils
    jq
  ];

  text = ''
    export FONTBUILDER_LIB=${./lib}
    export FONTBUILDER_DATA=${./data}
    export FONTBUILDER_SPECIMEN=${./specimen}
    export FONTBUILDER_TESTS=${./tests}
    export FONTBUILDER_LIGATURIZER=${ligaturizer}
    export FONTBUILDER_FIRA=${firaCode}/distr/otf
    export FONTBUILDER_DONOR_JBM=${jbmDir}
    export FONTBUILDER_DONOR_DEJAVU=${dejavu_fonts}/share/fonts/truetype
    export FONTBUILDER_DONOR_MAPLE=${maple-mono.NF}/share/fonts/truetype
    export FONTBUILDER_PYTHON=${py}/bin/python3
    exec ${py}/bin/python3 ${./fontbuilder.py} "$@"
  '';

  # The inertness proof, run at build time on every host: writeShellApplication's
  # default checks (shellDryRun + shellcheck — overriding checkPhase DROPS them,
  # so they are re-invoked here), a syntax check of both shell stages, a
  # byte-compile of every python module on a WRITABLE copy (compileall writes
  # __pycache__ beside the sources and the store is read-only), a JSON parse of
  # the donor table, and the 14 pinned source digests. None of it reads a font
  # and none of it needs ~/colors.
  checkPhase = ''
    runHook preCheck
    ${stdenv.shellDryRun} "$target"
    ${lib.getExe shellcheck-minimal} "$target"
    bash -n ${./lib}/ligaturize.sh
    bash -n ${./lib}/nerdpatch.sh
    cp -r ${./lib} ./_lib
    cp -r ${./tests} ./_tests
    cp ${./fontbuilder.py} ./_fontbuilder.py
    chmod -R u+w ./_lib ./_tests
    ${py}/bin/python3 -m compileall -q ./_lib ./_tests ./_fontbuilder.py
    ${py}/bin/python3 -c \
      'import json,sys; d=json.load(open(sys.argv[1])); assert d["fira_weight_map"] and d["weights"], "donor table incomplete"' \
      ${./data}/merge-blocks.json
    test "$(grep -c . ${./data}/sources.sha256)" -eq 14
    test -s ${./data}/anthropic-fonts.css
    runHook postCheck
  '';

  meta = {
    description = "Press the Anthropic font suite (recipe only — ships no font bytes)";
    longDescription = ''
      Instances the anthropic.com "Web" variable cuts to 12 statics, normalises
      names and style bits, completeness-merges from JetBrains Mono, DejaVu Sans
      Mono and Maple Mono NF, ligaturizes from Fira Code 3.001, re-seats each
      ligature against its own constituents, Nerd-patches last, restores the
      PUA glyphs the patcher overwrites, canonicalises head/FFTM for byte
      reproducibility, and packages three deterministic tarballs for
      nas:/mnt/fast/fonts/anthropic/.
    '';
    mainProgram = "fontbuilder";
    platforms = lib.platforms.linux;
  };
}
