{
  lib,
  symlinkJoin,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  glibc,
  gnugrep,
  gnused,
  ghostscript,
  imagemagick,
  jq,
  mupdf-headless,
  poppler-utils,
  sqlite,
  sqlite-vec,
}:
let
  chunkAwk = builtins.path {
    path = ./chunk.awk;
    name = "academic-ocr-chunk.awk";
  };
  fixtureDir = builtins.path {
    path = ./tests/fixtures;
    name = "academic-ocr-fixtures";
  };
  fixedPapers = builtins.path {
    path = ./fixed-papers.json;
    name = "academic-ocr-fixed-papers.json";
  };
  shellRuntime = [
    bash
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    jq
  ];

  signature = writeShellApplication {
    name = "academic-ocr-signature";
    runtimeInputs = shellRuntime ++ [ glibc.bin ];
    text = builtins.readFile ./signature.sh;
  };

  driver = writeShellApplication {
    name = "academic-ocr-driver";
    runtimeInputs = shellRuntime ++ [
      curl
      imagemagick
      mupdf-headless
      poppler-utils
      signature
      sqlite
    ];
    text = ''
      export ACADEMIC_OCR_CHUNK_AWK=${lib.escapeShellArg chunkAwk}
      export ACADEMIC_OCR_SQLITE_VEC=${lib.escapeShellArg "${sqlite-vec}/lib/vec0.so"}
      ${builtins.readFile ./driver.sh}
    '';
  };

  prepare = writeShellApplication {
    name = "academic-ocr-prepare";
    runtimeInputs = shellRuntime ++ [
      curl
      driver
      poppler-utils
    ];
    text = ''
      export ACADEMIC_OCR_DRIVER_PATH=${lib.escapeShellArg "${driver}/bin/academic-ocr-driver"}
      export ACADEMIC_OCR_PAPER_CATALOG=${lib.escapeShellArg fixedPapers}
      ${builtins.readFile ./prepare.sh}
    '';
  };

  planAssemble = writeShellApplication {
    name = "academic-ocr-plan-assemble";
    runtimeInputs = shellRuntime ++ [ driver ];
    text = ''
      export ACADEMIC_OCR_DRIVER_PATH=${lib.escapeShellArg "${driver}/bin/academic-ocr-driver"}
      ${builtins.readFile ./plan-assemble.sh}
    '';
  };

  fakeCurl = writeShellApplication {
    name = "academic-ocr-fake-curl";
    runtimeInputs = shellRuntime;
    text = builtins.readFile ./tests/fake-curl.sh;
  };

  tests = writeShellApplication {
    name = "academic-ocr-tests";
    runtimeInputs = shellRuntime ++ [
      driver
      fakeCurl
      ghostscript
      planAssemble
      prepare
      signature
      sqlite
    ];
    text = ''
      export ACADEMIC_OCR_FIXTURES=${lib.escapeShellArg fixtureDir}
      export ACADEMIC_OCR_FAKE_CURL=${lib.escapeShellArg "${fakeCurl}/bin/academic-ocr-fake-curl"}
      export ACADEMIC_OCR_PAPER_CATALOG=${lib.escapeShellArg fixedPapers}
      export ACADEMIC_OCR_SQLITE_VEC=${lib.escapeShellArg "${sqlite-vec}/lib/vec0.so"}
      exec ${bash}/bin/bash ${./tests/test-workflow.sh}
    '';
  };
in
symlinkJoin {
  name = "academic-ocr-1.0.0";
  paths = [
    driver
    planAssemble
    prepare
    signature
  ];
  postBuild = ''
    ${tests}/bin/academic-ocr-tests
  '';

  passthru = {
    inherit tests;
  };

  meta = {
    description = "Deterministic preparation and tally-flow driver for academic OCR";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "academic-ocr-prepare";
  };
}
