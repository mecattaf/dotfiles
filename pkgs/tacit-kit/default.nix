{ lib, stdenvNoCC, fetchFromGitHub }:
stdenvNoCC.mkDerivation {
  pname = "tacit-kit";
  version = "0-unstable-2026-11-02";
  src = fetchFromGitHub {
    owner = "ciscobugger";
    repo = "tacit-kit";
    rev = "f34574dae85aec2eb9e8835cc1dfece87cdfdf2d";
    hash = "sha256-WChPKXzk3awhbZ15Un+e1bCwhK51bReRlBUIJ3dYpvI=";
  };
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/share/tacit-kit $out/share/licenses/tacit-kit
    cp -r qml tools docs/examples generated $out/share/tacit-kit/
    cp LICENSE COPYING.GPL-3 TRADEMARKS.md $out/share/licenses/tacit-kit/
  '';
  meta = {
    description = "Tacit's QML components, bundled fonts, tokens and sample palettes";
    homepage = "https://github.com/ciscobugger/tacit-kit";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.linux;
  };
}
