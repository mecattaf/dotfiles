{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  git,
  gh,
  nix,
  coreutils,
  jq,
}:
let
  python = python3.withPackages (ps: [ ps.jsonschema ]);
in
stdenvNoCC.mkDerivation {
  pname = "local-ai-monthly";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    git
    jq
  ];
  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    ${python}/bin/python -m py_compile workflow.py
    ${jq}/bin/jq -e . sources.json schema/brief.schema.json >/dev/null
    ${python}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 workflow.py "$out/libexec/local-ai-monthly/workflow.py"
    install -Dm444 extension.ts "$out/libexec/local-ai-monthly/extension.ts"
    install -Dm444 sources.json "$out/libexec/local-ai-monthly/sources.json"
    install -Dm444 skill/SKILL.md "$out/libexec/local-ai-monthly/skill/SKILL.md"
    install -Dm444 schema/brief.schema.json "$out/libexec/local-ai-monthly/schema/brief.schema.json"

    makeWrapper ${python}/bin/python "$out/bin/local-ai-monthly" \
      --add-flags "$out/libexec/local-ai-monthly/workflow.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          gh
          nix
          coreutils
        ]
      }
    makeWrapper ${python}/bin/python "$out/bin/local-ai-monthly-tally" \
      --add-flags "$out/libexec/local-ai-monthly/workflow.py" \
      --add-flags "--publish" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          gh
          nix
          coreutils
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Deterministic monthly local-AI review executed through Pi and llama-swap";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "local-ai-monthly";
  };
}
