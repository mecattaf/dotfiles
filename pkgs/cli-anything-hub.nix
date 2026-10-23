{
  fetchFromGitHub,
  lib,
  python3Packages,
  uv,
  writableTmpDirAsHomeHook,
}:

python3Packages.buildPythonApplication rec {
  pname = "cli-anything-hub";
  version = "0.4.1-unstable-2026-07-09";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "HKUDS";
    repo = "CLI-Anything";
    rev = "bc536c9bebb7c3d9f7bb2736a732609139c1acdb";
    hash = "sha256-crrSNrbIIpGTBPrlPkzjUNMYhDtNiR0dMIOmWp+m9t4=";
  };

  sourceRoot = "source/cli-hub";

  patches = [ ./cli-anything-uv-tools.patch ];

  postPatch = ''
    substituteInPlace cli_hub/installer.py \
      --replace-fail '@uv@' '${uv}/bin/uv'
  '';

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    click
    requests
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    writableTmpDirAsHomeHook
  ];

  pythonImportsCheck = [ "cli_hub" ];

  # Keep each agent integration the fleet links tied to the exact same immutable
  # source revision as cli-hub. The NixOS module links these store trees into
  # each agent's normal discovery location; none of upstream's copy/install
  # scripts need to mutate $HOME.
  postInstall = ''
    share="$out/share/cli-anything"
    mkdir -p "$share"

    cp -R ../cli-anything-plugin "$share/claude-plugin"

    cp -R ../codex-skill "$share/codex-skill"
    chmod -R u+w "$share/codex-skill"
    mkdir -p \
      "$share/codex-skill/references/commands" \
      "$share/codex-skill/references/docs" \
      "$share/codex-skill/references/guides" \
      "$share/codex-skill/scripts/templates"
    cp ../cli-anything-plugin/HARNESS.md \
      "$share/codex-skill/references/HARNESS.md"
    cp ../cli-anything-plugin/commands/*.md \
      "$share/codex-skill/references/commands/"
    cp ../cli-anything-plugin/guides/*.md \
      "$share/codex-skill/references/guides/"
    cp ../cli-anything-plugin/repl_skin.py \
      ../cli-anything-plugin/preview_bundle.py \
      ../cli-anything-plugin/skill_generator.py \
      "$share/codex-skill/scripts/"
    cp ../cli-anything-plugin/templates/* \
      "$share/codex-skill/scripts/templates/"
    cp ../docs/PREVIEW_PROTOCOL.md \
      "$share/codex-skill/references/docs/PREVIEW_PROTOCOL.md"

    cp -R ../cli-hub-meta-skill "$share/cli-hub-meta-skill"
  '';

  meta = {
    description = "Agent-native CLI harness hub and CLI-Anything integrations";
    homepage = "https://github.com/HKUDS/CLI-Anything";
    license = lib.licenses.asl20;
    mainProgram = "cli-hub";
    platforms = lib.platforms.unix;
  };
}
