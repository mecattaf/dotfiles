{
  callPackage,
  fetchFromGitHub,
  symlinkJoin,
}:
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
  engine = upstream.overrideAttrs (_: {
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
  });
in
symlinkJoin {
  name = "superroc-fleet-${builtins.substring 0 7 revision}";
  paths = [ engine ];
  # Upstream preserves Gufo executable aliases during its rename. The fleet
  # installs both engines, so expose only SuperROC's own names in the profile.
  postBuild = ''
    rm -f "$out/bin/gufo" "$out/bin/gufo-server" "$out/bin/gufo-quant"
    test -x "$out/bin/superroc"
    test ! -e "$out/bin/gufo"
  '';
  passthru = { inherit engine; };
  meta = engine.meta;
}
