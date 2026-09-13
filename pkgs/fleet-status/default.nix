{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  openssh,
  util-linux,
}:
# fleet-status (#356): one stdlib Python file, two entry points.
#   fleet-status-collect  — installed on every host by modules/fleet-status.nix
#   fleet-status          — the coordinator's fan-out and terminal view
# The host's own systemctl/journalctl/findmnt come FIRST on PATH (suffix, not
# prefix): a collector must speak the systemd of the box it runs on, and the
# NAS rides a different nixpkgs than this package may be built from. openssh
# and util-linux are only fallbacks so the fan-out and runuser always resolve.
stdenvNoCC.mkDerivation {
  pname = "fleet-status";
  version = "1";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm0644 fleet_status.py $out/share/fleet-status/fleet_status.py
    install -Dm0644 SCHEMA.md $out/share/doc/fleet-status/SCHEMA.md
    for bin in fleet-status fleet-status-collect; do
      makeWrapper ${python3.interpreter} $out/bin/$bin \
        --add-flags "$out/share/fleet-status/fleet_status.py" \
        --argv0 $bin \
        --suffix PATH : ${
          lib.makeBinPath [
            openssh
            util-linux
          ]
        }
    done
    runHook postInstall
  '';
  meta = {
    description = "Bounded, graded snapshot of the fleet's systemd, journal, Nix, inference, Tally and Herdr state";
    mainProgram = "fleet-status";
  };
}
