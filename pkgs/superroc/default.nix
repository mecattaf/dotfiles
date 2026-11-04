{ callPackage, fetchFromGitHub }:
let
  revision = "5c2b07abd7c432e81180ed70edfa62ed7be4c105";
  source = fetchFromGitHub {
    owner = "kingjones30";
    repo = "superroc";
    rev = revision;
    sha256 = "14ismrw59ikab87alb0qw6cgha3z075lw2rm8pnykic14d7074fc";
  };
  upstream = callPackage "${source}/.devops/nix/package.nix" {
    revision = builtins.substring 0 7 revision;
  };
in
upstream.overrideAttrs (_: {
  # This revision's production filter omits the quantizer sources referenced
  # unconditionally by CMake. Retain the pinned source tree for configuration.
  src = source;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/superroc" --version | grep -F "Super ROC development (5c2b07a)"
    "$out/bin/superroc" --help >/dev/null
    test -f "$out/share/licenses/superroc/LICENSE"
    runHook postInstallCheck
  '';
  meta = upstream.meta // {
    description = "SuperROC inference backend for the custom ROCmFP4 Flash-Next GGUF";
  };
})
