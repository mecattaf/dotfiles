{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  dshModules,
}:
# The published JS is already transpiled. Every registry tarball is fixed by
# package-lock's integrity hash, including the independent Source/Strategy
# packages. No npm/pnpm, install scripts or network access during activation.
# Release v0.5.38 is upstream commit a4ad2d6955172b936ff9328f39cc5873c3ec9c55.
let
  lock = builtins.fromJSON (builtins.readFile ./package-lock.json);
  packages = builtins.removeAttrs lock.packages [ "" ];
  unpack = path: package: ''
    mkdir -p "$out/${path}"
    tar -xzf ${
      fetchurl {
        url = package.resolved;
        hash = package.integrity;
      }
    } \
      -C "$out/${path}" --strip-components=1
  '';
in
stdenvNoCC.mkDerivation {
  pname = "dsh-mnemon";
  version = "0.5.38";
  dontUnpack = true;
  nativeBuildInputs = [ nodejs ];
  installPhase = ''
    runHook preInstall
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList unpack packages)}
    # Root output is a DSH bundle directory, as with the other fleet plugins.
    cp -r "$out/node_modules/dsh-mnemon/". "$out/"
    rm -rf "$out/node_modules/dsh-mnemon"
    ln -s .. "$out/node_modules/dsh-mnemon"
    # Share DSH's exact peer instances (especially Cordis); no second runtime
    # or peer package version may be installed alongside the harness.
    for peer in ${dshModules}/*; do
      name="$(basename "$peer")"
      case "$name" in
        @*)
          mkdir -p "$out/node_modules/$name"
          for scoped in "$peer"/*; do
            target="$out/node_modules/$name/$(basename "$scoped")"
            if [ ! -e "$target" ]; then ln -s "$scoped" "$target"; fi
          done
          ;;
        *)
          if [ ! -e "$out/node_modules/$name" ]; then
            ln -s "$peer" "$out/node_modules/$name"
          fi
          ;;
      esac
    done
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node --input-type=module -e '
      const { createRequire } = await import("node:module");
      const require = createRequire(process.argv[1] + "/package.json");
      const m = require("./package.json");
      const semver = require("semver");
      if (m.version !== "0.5.38") throw new Error("unexpected Mnemon version");
      const dsh = require("@deepseek-ai/dsh-app-boot/package.json");
      if (!semver.satisfies(dsh.version, m.engines.dsh, { includePrerelease: true }))
        throw new Error("Mnemon does not support this DSH");
      await import(process.argv[1] + "/lib/index.js");
      await import(process.argv[1] + "/node_modules/dsh-mnemon-source-documents/lib/index.js");
      await import(process.argv[1] + "/node_modules/dsh-mnemon-provider-mnemon-native/lib/index.js");
    ' "$out"
    runHook postInstallCheck
  '';
  meta = {
    description = "Composable local memory for the dedicated DSH Mnemon profile";
    homepage = "https://github.com/omdsh-dev/dsh-mnemon";
    license = lib.licenses.mit;
  };
}
