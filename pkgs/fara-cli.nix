{
  lib,
  python3Packages,
  fetchFromGitHub,
  playwright-driver,
  callPackage,
}:

let
  # markitdown -> pdfplumber -> pandas-stubs, whose own test suite fails
  # against this nixpkgs pin's pytest (unrelated pre-existing breakage:
  # PytestRemovedIn10Warning from parametrize-with-a-generator in
  # pandas-stubs' vendored pandas test copies). overrideScope threads the
  # unchecked build through every consumer in this package set.
  pyPkgs = python3Packages.overrideScope (
    _pyfinal: pyprev: {
      pandas-stubs = pyprev.pandas-stubs.overridePythonAttrs (_: {
        doCheck = false;
        pythonImportsCheck = [ ];
      });
    }
  );
  browserbase = callPackage ./browserbase.nix { python3Packages = pyPkgs; };
in
# microsoft/fara — the reference CLI for the Fara1.5 computer-use-agent
# models (fara15-27b-q8-0 / fara15-9b-q8-0 / fara15-4b-q8-0 in
# lib/local-models.nix). It drives a real Chromium tab through Playwright,
# steered by an OpenAI-compatible chat endpoint; point it at the
# coordinator's own llama-swap server with --base_url/--model (see
# home/home.nix). No upstream release tags exist yet, so this pins the
# exact commit cloned 2026-08-03.
pyPkgs.buildPythonApplication rec {
  pname = "fara";
  version = "0-unstable-2026-07-22";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "fara";
    rev = "a675d6d61c41c47ae87bacefeab22caad18e3e84";
    hash = "sha256-TexN3pzrfdFYWO4+E6CEHk90WZs0Ceztp1Sdbss60Tk=";
  };

  build-system = [ pyPkgs.hatchling ];

  # Upstream pins playwright==1.51; nixpkgs carries a newer 1.x release and
  # the two speak the same wire protocol against playwright-driver's browser
  # binaries below, so relax rather than vendor a second Playwright.
  pythonRelaxDeps = [ "playwright" ];

  dependencies = with pyPkgs; [
    playwright
    openai
    pillow
    tenacity
    pyyaml
    jsonschema
    browserbase
    pydantic
    markitdown
    tiktoken
  ];

  # Fara only ever launches `browser_channel="chromium"` (run_fara.py); skip
  # firefox/webkit and point Playwright at the Nix-built binary instead of
  # its own mutable ~/.cache download.
  makeWrapperArgs = [
    "--set"
    "PLAYWRIGHT_BROWSERS_PATH"
    "${playwright-driver.browsers-chromium}"
    "--set"
    "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD"
    "1"
  ];

  pythonImportsCheck = [ "fara" ];

  meta = {
    description = "Reference CLI/agent harness for Microsoft's Fara1.5 computer-use models";
    homepage = "https://github.com/microsoft/fara";
    license = lib.licenses.mit;
    mainProgram = "fara-cli";
    platforms = lib.platforms.unix;
  };
}
