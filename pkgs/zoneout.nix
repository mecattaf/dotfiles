{ lib, fetchFromGitHub, python3Packages }:

python3Packages.buildPythonApplication {
  pname = "zoneout";
  version = "0.1.0-unstable-2026-10-24";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "marcinjakubowski";
    repo = "zoneout";
    rev = "49ebedb178f10c84c7e42e0e946c0ac971d08376";
    hash = "sha256-bZoEeR18O1ODkXbJilwReeGb2Pe6UslFts06P/URnt4=";
  };

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.hidapi ];
  pythonImportsCheck = [ "zoneout.device" "zoneout.cli" ];
  # The upstream checkout has no automated test suite.
  doCheck = false;
  # Upstream also declares a zoneout-gui entry point, which needs PyQt6. It is
  # not packaged here, so that binary would only crash: drop it.
  postInstall = "rm $out/bin/zoneout-gui";

  meta = {
    description = "Native Sony INZONE hardware volume, balance and noise controls";
    homepage = "https://github.com/marcinjakubowski/zoneout";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "zoneout";
  };
}
