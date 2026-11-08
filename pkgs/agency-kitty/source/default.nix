{
  lib,
  python3Packages,
  makeWrapper,
  openssh,
  fish,
  kitty,
  wl-clipboard,
  pipewire,
  mpv,
  fzf,
  holderPackage ? null,
}:
python3Packages.buildPythonApplication {
  pname = "agency-kitty";
  version = "0.1.0";
  pyproject = true;
  # Research receipts and build recipes remain in Git. Runtime source contains
  # only code/assets/usage, so changing a historical report neither rebuilds
  # this helper nor retains historical store closures in its output.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./agency_kitty ./kitty ./integration ./pyproject.toml ./LICENSE ./README.md
      ./docs/USAGE.md ./docs/HARNESS-LAUNCHERS.md ./docs/DIRECT_CATALOGUE.md ./docs/NATIVE_FORWARD.md
    ];
  };
  build-system = [ python3Packages.setuptools ];
  nativeBuildInputs = [ makeWrapper ];
  # Runtime-sensitive qualification is deliberately run through runtime-test on
  # compute. The Nix build checks imports and packages the exact reviewed tree.
  doCheck = false;
  pythonImportsCheck = [
    "agency_kitty.cli"
    "agency_kitty.catalogue"
    "agency_kitty.native_forward"
    "agency_kitty.native_forward_control"
  ];
  passthru = { kittyPackage = kitty; inherit holderPackage; };
  postInstall = ''
    mkdir -p $out/share/agency-kitty
    cp -r kitty $out/share/agency-kitty/
    cp -r integration $out/share/agency-kitty/
    substituteInPlace $out/share/agency-kitty/integration/dsh/cordis.patch.yml \
      --replace-fail '@AGENCY_KITTY_COMMAND@' "$out/bin/agency-kitty"
    substituteInPlace $out/share/agency-kitty/integration/agency-chat-window/native_catalogue.py \
      --replace-fail '@AGENCY_KITTY_COMMAND@' "$out/bin/agency-kitty"
    # Runtime usage travels with the tool; research receipts remain in the
    # source repository. Their historical build/store paths must not turn a
    # small terminal helper into a retention root for unrelated build tools.
    mkdir -p $out/share/agency-kitty/docs
    cp docs/USAGE.md docs/HARNESS-LAUNCHERS.md docs/DIRECT_CATALOGUE.md docs/NATIVE_FORWARD.md \
      $out/share/agency-kitty/docs/
    cp README.md LICENSE $out/share/agency-kitty/
  '';
  postFixup = ''
    for program in agency-kitty agency-kitty-native-forward agency-kitty-native-control; do
      wrapProgram "$out/bin/$program" \
      --prefix PATH : ${lib.makeBinPath ([ openssh fish kitty wl-clipboard pipewire mpv fzf ] ++ lib.optional (holderPackage != null) holderPackage)} \
      --set AGENCY_KITTY_COMMAND $out/bin/agency-kitty \
      --set AGENCY_KITTY_KITTEN ${kitty}/bin/kitten \
      --set AGENCY_KITTY_BINARY ${kitty}/bin/kitty \
      --set AGENCY_KITTY_FISH_INTEGRATION_DIR ${kitty}/lib/kitty/shell-integration \
      --set TERMINFO ${kitty}/lib/kitty/terminfo \
      --set AGENCY_KITTY_ASSET_ROOT $out/share/agency-kitty \
      --set AGENCY_NATIVE_FORWARD_CONTROL agency-kitty-native-control \
      ${lib.optionalString (holderPackage != null) "--set AGENCY_KITTY_ZMX_BINARY ${holderPackage}/bin/zmx --set AGENCY_KITTY_HOLDER_VERSION ${holderPackage.version}"}
    done
  '';
  meta = {
    description = "Native Kitty transport and DSH/Imagine workflow extensions";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "agency-kitty";
  };
}
