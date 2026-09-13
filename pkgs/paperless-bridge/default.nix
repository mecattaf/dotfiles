# Same-inode projection bridge between the canonical NAS document tree and
# Paperless-ngx v3 (dotfiles#136). Two binaries: the unprivileged bridge CLI
# (scan/ingest/relink/enrich/suggest/sync-tags/verify/audit/bulk) and the
# narrow root relink helper it calls through a restricted sudo rule. The
# versioned tag taxonomy ships alongside as the vocabulary authority.
#
# The fixture suite (test_bridge.py: real catalog layout, fake Paperless API,
# fake utility model) runs as the install check, so every host that installs
# the bridge — nas, and the coordinator for `suggest` — refuses to build a
# bridge whose enrichment, tag round-trip or bulk guards regressed.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  # The concrete served model id `suggest` records beside each candidate
  # (the utility-model wrapper answers as the stable id `utility`).
  suggestModelId ? "utility",
}:
stdenvNoCC.mkDerivation {
  pname = "paperless-bridge";
  version = "2026-09-13";
  src = builtins.path {
    path = ./.;
    name = "paperless-bridge-src";
    filter = path: _type: builtins.baseNameOf path != "default.nix";
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    lib=$out/libexec/paperless-bridge
    mkdir -p $lib $out/bin
    cp $src/bridge.py $src/relink-helper.py $src/taxonomy.json $lib/
    chmod +x $lib/bridge.py $lib/relink-helper.py

    makeWrapper ${python3}/bin/python3 $out/bin/paperless-bridge \
      --add-flags $lib/bridge.py \
      --set-default BRIDGE_TAXONOMY $lib/taxonomy.json \
      --set-default BRIDGE_SUGGEST_MODEL ${lib.escapeShellArg suggestModelId}
    makeWrapper ${python3}/bin/python3 $out/bin/paperless-relink-helper \
      --add-flags $lib/relink-helper.py
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # unittest takes a module name here: an absolute file path is misread as
    # one ("No module named '/build/test_bridge'").
    cp $src/test_bridge.py $TMPDIR/
    (cd $TMPDIR && BRIDGE_UNDER_TEST=$out/libexec/paperless-bridge/bridge.py \
      ${python3}/bin/python3 -m unittest -v test_bridge)
    runHook postInstallCheck
  '';
  meta = {
    description = "same-inode canonical-PDF projection into Paperless-ngx, with verified relink and receipts";
    platforms = lib.platforms.linux;
  };
}
