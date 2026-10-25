{ lib, buildNpmPackage, bun, nodejs_24, autoPatchelfHook, makeWrapper,
  stdenv, libxkbcommon, wayland, vulkan-loader, fontconfig, freetype,
  libGL, xorg, openssl, hyprland, glib, wireplumber, cliphist, wl-clipboard }:
buildNpmPackage {
  pname = "desktop-shell";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: !(builtins.elem (baseNameOf path) [ "node_modules" "dist" "result" ]);
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-HJ0+ycf4usEOgFB2Thzyv5G9TcMcyIi1Y2lkijrAJn8=";
  npmFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [ bun autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib libxkbcommon ];
  dontNpmPrune = true;
  doCheck = true;
  # Pure mocked-controller tests: no compositor, socket or service is launched.
  checkPhase = ''
    runHook preCheck
    bun test
    runHook postCheck
  '';
  buildPhase = ''
    runHook preBuild
    npm run typecheck
    bun run build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/desktop-shell $out/bin
    cp -r dist node_modules package.json $out/lib/desktop-shell/
    makeWrapper ${bun}/bin/bun $out/bin/desktop-shell \
      --add-flags "$out/lib/desktop-shell/dist/main.js" \
      --set DESKTOP_SHELL_EXECUTABLE "$out/bin/desktop-shell" \
      --prefix PATH : ${lib.makeBinPath [ hyprland glib wireplumber cliphist wl-clipboard ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib libxkbcommon wayland vulkan-loader fontconfig freetype libGL xorg.libX11 xorg.libxcb openssl ]}
    runHook postInstall
  '';
  meta = {
    description = "Native SolidJS GPUIX desktop shell for Hyprland";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "desktop-shell";
  };
}
