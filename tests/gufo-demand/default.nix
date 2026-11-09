{ pkgs, self }:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  proxy = c.services.llama-swap;
  models = proxy.settings.models;
  extended =
    (self.nixosConfigurations.strix-coordinator.extendModules {
      modules = [
        {
          services.gufo.models."qwen27-short" = {
            artifact = "qwen38-27b-gguf";
            dflashArtifact = "qwen38-27b-dflash2-gguf";
            serve = {
              context = 32768;
              sessions = 1;
              think = "off";
            };
            idleSeconds = 180;
          };
        }
      ];
    }).config;
  extra = extended.services.llama-swap.settings.models."qwen27-short";
  ids = [
    "Qwen-Image-2.1"
    "qwen3-asr-1.7b"
    "qwen3-tts-12hz-1.7b-base"
    "qwen3.8-27b"
    "qwen3.8-27b-q8"
    "qwen3.8-flash-next"
  ];
  worker = self.nixosConfigurations.strix-worker.config;
  hy = models."hy-memory-30b-a3b";
  loans = [
    "qwen38-27b-heretic-ara-q8-gguf"
    "qwen38-flash-next-abliterated-rocmfp4-gguf"
  ];
in
assert proxy.enable && proxy.port == 8731;
# The ARA and abliterated Flash-Next loans are returned (Tom, 2026-11-09,
# #603): no route and no wanted entry remain, so the next prune names them.
# Their catalogue rows and Library bytes stay; SuperROC stays dormant.
assert !c.services.superroc.enable;
assert !(models ? "qwen3.8-27b-ara");
assert !(models ? "qwen3.8-flash-next-abliterated");
assert builtins.all (id: !(builtins.elem id c.services.local-models.artifacts)) loans;
assert !worker.services.superroc.enable;
assert builtins.all (id: !(builtins.elem id worker.services.local-models.artifacts)) loans;
# Hy-Memory is a plain llama-server route behind the same supervisor, borrowed
# from the Library and never fetched by the server itself.
assert c.services.hy-memory.enable;
assert builtins.elem "hy-memory-30b-a3b-q8-gguf" c.services.local-models.artifacts;
assert hy.checkEndpoint == "/health" && hy.ttl == 600;
assert hy.useModelName == "hy-memory-30b-a3b";
assert hy.capabilities.context == 65536 && hy.capabilities.tools == false;
assert !(pkgs.lib.hasInfix "-hf" hy.cmd);
assert pkgs.lib.hasSuffix "-llama-server-demand-hy-memory \${PORT}" hy.cmd;
# Reached only through its launcher: the fleet's llama-server stays on PATH.
assert !(builtins.elem c.services.hy-memory.package c.environment.systemPackages);
assert !worker.services.hy-memory.enable;
assert !(worker.services.llama-swap.settings.models ? "hy-memory-30b-a3b");
assert !(builtins.elem "hy-memory-30b-a3b-q8-gguf" worker.services.local-models.artifacts);
# Gufo and the production qwentts.cpp voice share one loan, not duplicate IDs.
assert
  builtins.length (builtins.filter (id: id == "qwen-k2so-midway-b") c.services.local-models.artifacts)
  == 1;
assert builtins.all (id: builtins.hasAttr id models) ids;
assert !(proxy.settings ? hooks) && !(proxy.settings ? groups);
assert models."qwen3.8-flash-next".ttl == 600;
assert models."qwen3-tts-12hz-1.7b-base".ttl == 120;
assert models."qwen3-asr-1.7b".ttl == 120;
assert models."qwen3.8-27b-q8".useModelName == "qwen3.8-27b";
assert models."qwen3.8-flash-next".capabilities.context == 102400;
assert builtins.all (id: models.${id}.checkEndpoint == "/ready" && models.${id}.ttl > 0) ids;
assert c.systemd.services.gufo-llm.wantedBy == [ ];
assert c.systemd.services.llama-swap.wantedBy == [ "multi-user.target" ];
assert !(c.systemd.services ? gufo-tp2);
assert !(c.systemd.services ? ds4);
assert !(builtins.elem proxy.port c.networking.firewall.allowedTCPPorts);
assert builtins.all (id: builtins.hasAttr id extended.services.llama-swap.settings.models) ids;
assert extra.ttl == 180 && extra.capabilities.context == 32768;
assert extra.useModelName == "qwen27-short";
assert builtins.elem "qwen38-27b-gguf" extended.services.local-models.artifacts;
assert builtins.elem "qwen38-27b-dflash2-gguf" extended.services.local-models.artifacts;
pkgs.runCommand "gufo-demand"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (p: [ p.pillow ]))
      proxy.package
    ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    export LLAMA_SWAP=${proxy.package}/bin/llama-swap
    python3 ${./test_lifecycle.py} -v
    export PYTHONPATH=${../../lib/python}:${../../pkgs/handwriting-intake}
    export LOCAL_MODEL_ENDPOINT=http://127.0.0.1:1
    python3 -m unittest discover -s ${../../pkgs/handwriting-intake} -p test_intake.py -v
    touch "$out"
  ''
