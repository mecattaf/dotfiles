{
  lib,
  pkgs,
  modelStore,
}:
let
  dirOf = id: modelStore.materialized.${id}.directory;
in
ids:
pkgs.writeShellScript "gufo-bundle-check" ''
  set -eu
  fail=0
  ${lib.concatMapStringsSep "\n" (
    id:
    lib.concatMapStringsSep "\n" (f: ''
      p=${lib.escapeShellArg "${dirOf id}/${f.name}"}
      if [ ! -r "$p" ] || [ "$(${pkgs.coreutils}/bin/stat -c %s "$p")" != ${toString f.bytes} ]; then
        echo "gufo: missing or wrong size: $p (want ${toString f.bytes} bytes); run: sudo local-models-borrow --yes" >&2
        fail=1
      fi
    '') modelStore.materialized.${id}.files
  ) ids}
  exit "$fail"
''
