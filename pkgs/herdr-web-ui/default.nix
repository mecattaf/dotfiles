{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  nodejs_24,
  cacert,
  autoPatchelfHook,
  makeWrapper,
  revision,
  sourceHash,
  depsHash,
}:
let
  # Immutable private fork. Builds run on strix; an authenticated GitHub CLI
  # prefetch can warm this fixed-output source without daemon credentials.
  src = fetchFromGitHub {
    owner = "mecattaf";
    repo = "herdr-web-ui";
    rev = revision;
    hash = sourceHash;
    private = true;
  };
  deps = stdenvNoCC.mkDerivation {
    pname = "herdr-web-ui-deps";
    version = revision;
    inherit src;
    nativeBuildInputs = [
      bun
      cacert
    ];
    dontConfigure = true;
    dontBuild = true;
    # This fixed-output tree must be independent of the builder's Nix paths.
    # Final-package fixup patches interpreters and native libraries after copy.
    dontFixup = true;
    installPhase = ''
      export HOME="$TMPDIR/home"
      export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
      bun install --frozen-lockfile --ignore-scripts --no-progress
      cp -R node_modules "$out"
    '';
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = depsHash;
  };
in
stdenv.mkDerivation {
  pname = "herdr-web-ui";
  version = revision;
  inherit src;
  nativeBuildInputs = [
    bun
    nodejs_24
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    cp -R ${deps} node_modules
    chmod -R u+w node_modules
    # Bun retains both libc variants of optional native dependencies. This
    # GNU/Linux package uses only the GNU variants, never the musl binaries.
    rm -r node_modules/lightningcss-linux-x64-musl node_modules/@rolldown/binding-linux-x64-musl
    patchShebangs node_modules
    autoPatchelf node_modules
    bun run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/herdr-web-ui" "$out/bin"
    cp -R server shared src dist node_modules package.json "$out/lib/herdr-web-ui/"
    cp ${./entrypoint.ts} "$out/lib/herdr-web-ui/server/nix.ts"
    makeWrapper ${lib.getExe bun} "$out/bin/herdr-web-ui" \
      --add-flags "$out/lib/herdr-web-ui/server/nix.ts" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]}
    runHook postInstall
  '';
  meta = {
    description = "Tom's private Herdr web UI, served from an immutable build";
    license = lib.licenses.mit;
    mainProgram = "herdr-web-ui";
    platforms = [ "x86_64-linux" ];
  };
}
