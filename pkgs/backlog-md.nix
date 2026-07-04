# Backlog.md — markdown-native task manager / kanban CLI (`backlog`).
#
# Not in nixpkgs (checked 2026-07-04) — re-check occasionally and drop this
# file when it lands. Upstream is a Bun app compiled to a single executable;
# building from source under Nix means wrangling a Bun node_modules FOD, so we
# take the release binary instead. It only links glibc (libc/libm/libpthread/
# libdl), so autoPatchelfHook needs no extra buildInputs. The x64 asset is
# "-baseline" (no AVX2 requirement) — upstream ships no non-baseline linux-x64.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  sources = {
    x86_64-linux = {
      asset = "backlog-bun-linux-x64-baseline";
      hash = "sha256-TKuBto+Bk/G+fkzUvnB93LiI5qBqPUkDPI2aCF79Qks=";
    };
    aarch64-linux = {
      asset = "backlog-bun-linux-arm64";
      hash = "sha256-UeP8GIEaVvOgeSVW9cA4HupG1x3epBaJ5wD+gXfX0YY=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "backlog-md: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "backlog-md";
  version = "1.47.1";

  src = fetchurl {
    url = "https://github.com/MrLesk/Backlog.md/releases/download/v${finalAttrs.version}/${source.asset}";
    inherit (source) hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontUnpack = true;
  dontStrip = true; # Bun single-file executables embed the JS bundle; strip corrupts it

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/backlog
    runHook postInstall
  '';

  meta = {
    description = "Markdown-native task manager and kanban visualizer for git repositories";
    homepage = "https://github.com/MrLesk/Backlog.md";
    changelog = "https://github.com/MrLesk/Backlog.md/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
    mainProgram = "backlog";
  };
})
