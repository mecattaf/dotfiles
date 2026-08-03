{
  lib,
  python3Packages,
  fetchPypi,
}:

# Not in nixpkgs (2026-08-03). Only transitive dependency `fara-cli` needs it
# for: microsoft/fara imports `browserbase` unconditionally at module load
# (src/fara/fara_7b/browser/browser_bb.py), even though the local Playwright
# path never calls into it. A plain Stainless-generated OpenAI-style SDK
# client; packaging it directly is simpler than patching upstream's import.
python3Packages.buildPythonPackage rec {
  pname = "browserbase";
  version = "1.15.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-04Yd5bvsOGAyOIENr2vEnTY3vezgrQ53A1Gf/35471I=";
  };

  # Upstream's build-system pin (hatchling==1.26.3) is stricter than the
  # dependency pin relaxed by pythonRelaxDeps below, and only applies before
  # the package's own build backend runs, so drop it by hand.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'hatchling==1.26.3' 'hatchling'
  '';

  build-system = with python3Packages; [
    hatchling
    hatch-fancy-pypi-readme
  ];

  dependencies = with python3Packages; [
    anyio
    distro
    httpx
    pydantic
    sniffio
    typing-extensions
  ];

  pythonImportsCheck = [ "browserbase" ];

  meta = {
    description = "Python SDK for the Browserbase headless-browser API";
    homepage = "https://pypi.org/project/browserbase/";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
