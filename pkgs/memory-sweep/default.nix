{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  jq,
  podman,
  python3,
  util-linux,
  llamaCppVulkan,
  aiMemoryEngine,
}:
# memory-sweep (DECISIONS.md 2026-10-17): the bounded, hand-run trial of a
# memory writer over the T-15 sweep sample. Two commands:
#
#   memory-sweep-sample  plan | run | report <run-id> | clean <run-id>
#     N markdown files from ~/notes plus N chat jsonl from ~/archives, run once
#     through TencentDB-Agent-Memory's MemoryCore image (by digest, podman,
#     SQLite, embeddings off) behind the Hy-Memory writer; everything it writes
#     lands under ~/.local/state/memory-sweep/<run-id>/. Nothing scheduled.
#
#   hy-memory-serve
#     the hand-run llama-server for the hy-memory-30b-a3b-q8-0 catalogue row.
#     It wraps nixpkgs' llama-cpp (build 10063, Vulkan) by store path because
#     the fleet's gfx1151 llama.cpp from nix-strix-halo is build 9925, 68
#     commits before llama.cpp merged hy_v3. The fleet's `llama-server` on
#     PATH is untouched; this one is reached only through the wrapper.
#
# The chat normaliser is the drain skill's tested ai_memory.py, passed in by
# path so the pin is visible in the overlay; there is no second jsonl parser.
let
  coreImage = "docker.io/agentmemory/memory-core@sha256:b37fa9f2e1e4993ab69e2b4522ec5897f075a7031e01e31fed080acdcaf96c98";
  llamaServer = "${llamaCppVulkan}/bin/llama-server";
in
stdenvNoCC.mkDerivation {
  pname = "memory-sweep";
  version = "2026-10-17";
  src = builtins.path {
    path = ./.;
    name = "memory-sweep-src";
    filter = path: _type: builtins.baseNameOf path != "default.nix";
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    lib=$out/libexec/memory-sweep
    mkdir -p $lib $out/bin
    install -Dm0644 memory_sweep.py $lib/memory_sweep.py
    install -Dm0644 tdai-gateway.template.yaml $lib/tdai-gateway.template.yaml
    install -Dm0755 hy-memory-serve.sh $lib/hy-memory-serve.sh

    makeWrapper ${python3.interpreter} $out/bin/memory-sweep-sample \
      --add-flags "$lib/memory_sweep.py" \
      --argv0 memory-sweep-sample \
      --set-default MEMORY_SWEEP_LLAMA_SERVER ${llamaServer} \
      --set-default MEMORY_SWEEP_AI_MEMORY ${aiMemoryEngine} \
      --set-default MEMORY_SWEEP_CORE_IMAGE ${coreImage} \
      --set-default MEMORY_SWEEP_SERVE "$lib/hy-memory-serve.sh" \
      --set-default MEMORY_SWEEP_TEMPLATE "$lib/tdai-gateway.template.yaml" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          curl
          jq
          podman
          python3
          util-linux
        ]
      }

    makeWrapper ${bash}/bin/bash $out/bin/hy-memory-serve \
      --add-flags "$lib/hy-memory-serve.sh" \
      --argv0 hy-memory-serve \
      --set-default MEMORY_SWEEP_LLAMA_SERVER ${llamaServer} \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          util-linux
        ]
      }
    runHook postInstall
  '';
  passthru = {
    inherit llamaServer coreImage;
    llamaServerVersion = llamaCppVulkan.version;
  };
  meta = {
    description = "Bounded, hand-run trial of the Hy-Memory writer behind TencentDB-Agent-Memory over the T-15 sweep sample";
    platforms = lib.platforms.linux;
    mainProgram = "memory-sweep-sample";
  };
}
