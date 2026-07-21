# llama-swap — the native proxy/control plane for local model backends.
#
# nixos-unstable is still on v224 as of 2026-07-21, while upstream stable is
# v240. Use upstream's official, statically linked release binary so the serving
# tier gets the current scheduler/UI fixes without moving the fleet's deliberately
# lagging kernel/Mesa nixpkgs pin. The hashes are the SHA-256 digests published on
# the GitHub release assets.
{
  lib,
  stdenvNoCC,
  fetchurl,
  versionCheckHook,
}:

let
  sources = {
    x86_64-linux = {
      asset = "llama-swap_240_linux_amd64.tar.gz";
      hash = "sha256-Pgw/0mSfKw60F6srwzfaZeO7tTdPrpdp50q5C9qjc5w=";
    };
    aarch64-linux = {
      asset = "llama-swap_240_linux_arm64.tar.gz";
      hash = "sha256-Gnz5Y2GuhJqyy7gIBiFEvkkNfGVFTXiW/TGOV1xRcu0=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "llama-swap: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "llama-swap";
  version = "240";

  src = fetchurl {
    url = "https://github.com/mostlygeek/llama-swap/releases/download/v${finalAttrs.version}/${source.asset}";
    inherit (source) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 llama-swap "$out/bin/llama-swap"
    install -Dm644 README.md "$out/share/doc/llama-swap/README.md"
    install -Dm644 LICENSE.md "$out/share/licenses/llama-swap/LICENSE.md"
    runHook postInstall
  '';

  doInstallCheck = true;
  versionCheckProgramArg = "-version";

  meta = {
    description = "Reliable model swapping for local OpenAI/Anthropic-compatible servers";
    homepage = "https://github.com/mostlygeek/llama-swap";
    changelog = "https://github.com/mostlygeek/llama-swap/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
    mainProgram = "llama-swap";
  };
})
