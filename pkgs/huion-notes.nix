{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  imagemagick,
  makeWrapper,
}:

let
  # dbus-fast is the whole of the live `dump` path's non-stdlib surface
  # (huion_ble_driver.BLEConnection talks to BlueZ over the system bus).
  python = python3.withPackages (ps: [ ps.dbus-fast ]);

  src = fetchFromGitHub {
    owner = "Reginleif88";
    repo = "huion-note-x10-ble";
    rev = "6f3f5e73fbb776dabeea54f54b411690a1c14091";
    hash = "sha256-I00+MUXOmKj1DSwy2MRjT58NlKpGqrqu6qMyL5XnRtk=";
  };
in
# Reginleif88/huion-note-x10-ble — a reverse-engineered BLE extractor for the
# Huion Note X10's offline notes: `huion-notes dump -o DIR` pulls every stored
# page as page{N}-{DD}-{MM}.{svg,png,json} and, unless --keep, deletes each
# page from the device once its SVG and JSON are on disk. Consumed by
# hosts/client/huion.nix, which also takes the BlueZ patch from this same pin
# (passthru.bluezPatch) so the extractor and the daemon fix cannot drift.
#
# Not a Python project upstream (no pyproject, no release tags): the package
# directory plus huion_ble_driver.py, which huion_notes/transport.py imports,
# go on PYTHONPATH as they are. Pinned to the exact commit proven end to end on
# the client on 2026-09-13 (~/huion/HANDOFF.md on the coordinator).
#
# Upstream's README is stale for this unit: it says "cover closed" for note
# mode (the X10 syncs with the cover OPEN, LED green; closed is asleep) and
# references a modules/huion-ble.nix that does not exist. The launcher
# huion-x10-notes.sh (nix-shell, pen-driver unit juggling) is not installed.
stdenvNoCC.mkDerivation {
  pname = "huion-notes";
  version = "0-unstable-2026-07-10";

  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  # Thin strokes — Tom's pick (b) of four width samples on 2026-09-13: 1.2 on
  # the extractor's 900 px canvas (upstream 2.5), round caps and joins as in
  # the sample he chose. The PNG is rasterised from this SVG, so it inherits
  # the width. --replace-fail so an upstream bump that rewrites the line fails
  # the build instead of silently going back to thick ink.
  postPatch = ''
    substituteInPlace huion_notes/render.py --replace-fail \
      'stroke="#111" stroke-width="2.5"/>' \
      'stroke="#111" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>'
  '';

  dontBuild = true;

  # Stdlib unittest, no device needed; test_render still passes with the
  # width patch (it asserts structure, not attributes).
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python.interpreter} -m unittest discover -s . -p 'test_*.py'
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/huion-notes
    cp -r huion_notes huion_ble_driver.py $out/lib/huion-notes/
    rm -f $out/lib/huion-notes/huion_notes/test_*.py
    # magick on PATH or the PNGs are skipped with only a warning.
    makeWrapper ${python.interpreter} $out/bin/huion-notes \
      --add-flags "-m huion_notes" \
      --prefix PYTHONPATH : $out/lib/huion-notes \
      --prefix PATH : ${lib.makeBinPath [ imagemagick ]}
    runHook postInstall
  '';

  # Two lines of src/shared/att.c: drop the X10's duplicate ATT MTU request
  # instead of shutting the link down. Still needed on BlueZ 5.86.
  passthru.bluezPatch = "${src}/patches/fix-duplicate-mtu-request.patch";

  meta = {
    description = "Offline note extractor for the Huion Note X10 over BLE";
    homepage = "https://github.com/Reginleif88/huion-note-x10-ble";
    license = lib.licenses.mit;
    mainProgram = "huion-notes";
    platforms = lib.platforms.linux;
  };
}
