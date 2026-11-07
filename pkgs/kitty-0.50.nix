# Qualified candidate only; no host or global nixpkgs override.
{ pkgs }:
let
  version = "0.50.0";
  src = pkgs.fetchFromGitHub {
    owner = "kovidgoyal";
    repo = "kitty";
    tag = "v${version}";
    hash = "sha256-CSSjL931OLZ9wwz9E3rAfMcm+TpczVJzJh9MPfuKmVU=";
  };
  modules = pkgs.buildGo126Module {
    pname = "kitty-go-modules";
    inherit version src;
    vendorHash = "sha256-Oo5ehjdq4HcTxZcKi/rwz8dDZYGxdSS8cqIkbdLBrb8=";
  };
in pkgs.kitty.overrideAttrs (old: {
  inherit version src;
  patches = old.patches ++ [ ./kitty-memory-procfs-fallback.patch ];
  goModules = modules.goModules;
  nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.shader-slang pkgs.python3Packages.sphinx-design ];
  postFixup = (old.postFixup or "") + ''
    wrapProgram $out/bin/kitty --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.shader-slang ]}
  '';
})
