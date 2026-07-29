# Production academic-OCR drain: the paper-e2e tally flow, its bounded shell
# tools, and the three drivers (work-list builder, serial drain loop, notes
# absorber). Code lives in the store; all mutable state stays in
# ~/.local/state/academic-ocr (dataRoot). Supersedes the unversioned state-root
# copies this shipped from (2026-07-29).
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  gawk,
  git,
  jq,
  mupdf-headless,
  poppler-utils,
  python3,
  util-linux,
  tally,
}:
stdenvNoCC.mkDerivation {
  pname = "academic-ocr-drain";
  version = "2026-07-29";
  src = builtins.path {
    path = ./.;
    name = "academic-ocr-drain-src";
    filter = path: _type: builtins.baseNameOf path != "default.nix";
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    lib=$out/libexec/academic-ocr-drain
    mkdir -p $lib $out/bin
    cp -r $src/. $lib/
    chmod +x $lib/*.sh $lib/*.py

    # env.sh is generated, not copied: every tool resolves its binaries
    # through these pins, so the whole ladder rebuilds against nixpkgs.
    cat > $lib/env.sh <<EOF
    POPPLER=${poppler-utils}/bin
    MUPDF=${mupdf-headless}/bin
    JQ=${jq}/bin/jq
    CURL=${curl}/bin/curl
    CORE=${coreutils}/bin
    AWK=${gawk}/bin/gawk
    LLAMA_SWAP=http://127.0.0.1:9292
    EOF

    makeWrapper ${bash}/bin/bash $out/bin/academic-drain \
      --add-flags $lib/drain.sh \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          git
          jq
          python3
          util-linux
          tally
        ]
      }
  '';
  meta = {
    description = "tally paper-e2e OCR flow with drain, work-list, and notes-absorption drivers";
    platforms = lib.platforms.linux;
  };
}
