{
  lib,
  stdenvNoCC,
  cacert,
  linkFarm,
  removeReferencesTo,
  runCommand,
  zig,
  # The zmx source tree (a non-flake input pinned in flake.lock).
  src,
}:

# zmx built directly with the nixpkgs zig toolchain, WITHOUT upstream's flake.
#
# Upstream packages itself through Cloudef/zig2nix, whose `env.package` parses
# build.zig.zon and converts the dependency lock via import-from-derivation:
# every `nix flake check`/eval of a consumer then has to BUILD zon2json/zon2nix
# helpers mid-eval. That made our evals slow, broke `--no-build` runs outright,
# and left them one GC away from "path 'zon2json.drv' is not valid"
# (hit live 2026-08-20). This file replaces the IFD with a pure-eval read of
# upstream's committed build.zig.zon2json-lock: same lock, same hashes, zero
# eval-time builds.
#
# The lock format and the fetch recipe below mirror what zig2nix's zon2nix
# generates for zig >= 0.16: each dependency is one fixed-output `zig fetch`
# whose flat sha256 is recorded in the lock, and the global cache's p/ dir is
# a linkFarm of "<zig-hash>.tar.gz" entries. Bumping zmx = `nix flake update
# zmx`; if upstream regenerated its lock the new hashes ride along for free.

let
  lock = builtins.fromJSON (builtins.readFile "${src}/build.zig.zon2json-lock");

  zonLines = lib.splitString "\n" (builtins.readFile "${src}/build.zig.zon");
  matchZonField =
    field: line: builtins.match "[[:space:]]*\\.${field} = \"([^\"]+)\",?[[:space:]]*" line;
  zonField =
    field:
    let
      hit = lib.findFirst (line: matchZonField field line != null) null zonLines;
    in
    if hit == null then
      throw "zmx: build.zig.zon has no .${field} field"
    else
      builtins.head (matchZonField field hit);

  fetchZig =
    {
      name,
      url,
      hash,
    }:
    runCommand "${name}.tar.gz"
      {
        nativeBuildInputs = [ zig ];
        outputHash = hash;
        outputHashMode = "flat";
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        impureEnvVars = lib.fetchers.proxyImpureEnvVars;
      }
      ''
        touch "$TMPDIR/build.zig" # zig fetch wants a project root
        hash="$(cd "$TMPDIR" && zig fetch --global-cache-dir "$TMPDIR" ${lib.escapeShellArg url})"
        mv "$TMPDIR/p/$hash.tar.gz" "$out"
      '';

  deps = linkFarm "zmx-dependencies" (
    lib.mapAttrsToList (zigHash: dep: {
      name = "${zigHash}.tar.gz";
      path = fetchZig { inherit (dep) name url hash; };
    }) lock
  );
in
stdenvNoCC.mkDerivation {
  pname = "zmx";
  version = zonField "version";
  inherit src;

  nativeBuildInputs = [
    zig.hook
    removeReferencesTo
  ];

  # Static musl binary, as upstream's own Linux package (zigPreferMusl).
  zigBuildFlags = [ "-Dtarget=x86_64-linux-musl" ];

  postConfigure = ''
    ln -s ${deps} "$ZIG_GLOBAL_CACHE_DIR"/p
  '';

  postFixup = ''
    find "$out" -type f -exec remove-references-to -t ${zig} '{}' +
  '';

  disallowedReferences = [
    zig
    zig.hook
    removeReferencesTo
    deps
  ];

  meta = {
    description = "Session persistence for terminal processes (built without zig2nix IFD)";
    homepage = "https://github.com/neurosnap/zmx";
    license = lib.licenses.mit;
    mainProgram = "zmx";
    platforms = [ "x86_64-linux" ];
  };
}
