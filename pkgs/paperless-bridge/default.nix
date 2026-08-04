# Same-inode projection bridge between the canonical NAS document tree and
# Paperless-ngx v3 (dotfiles#136). Two binaries: the unprivileged bridge CLI
# (scan/ingest/relink/enrich/sync-tags/verify/audit) and the narrow root
# relink helper it calls through a restricted sudo rule. The versioned tag
# taxonomy ships alongside as the vocabulary authority.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "paperless-bridge";
  version = "2026-08-04";
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
      --set-default BRIDGE_TAXONOMY $lib/taxonomy.json
    makeWrapper ${python3}/bin/python3 $out/bin/paperless-relink-helper \
      --add-flags $lib/relink-helper.py
  '';
  meta = {
    description = "same-inode canonical-PDF projection into Paperless-ngx, with verified relink and receipts";
    platforms = lib.platforms.linux;
  };
}
