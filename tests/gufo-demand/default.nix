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
    "qwen3.8-27b-ara"
    "qwen3.8-27b-q8"
    "qwen3.8-flash-next"
    "qwen3.8-flash-next-abliterated"
  ];
in
assert proxy.enable && proxy.port == 8731;
# Preserve the qualified runtime-only routes across the first declarative boot.
assert c.services.superroc.enable;
assert !self.nixosConfigurations.strix-worker.config.services.superroc.enable;
assert !(builtins.elem "qwen38-27b-heretic-ara-q8-gguf" self.nixosConfigurations.strix-worker.config.services.local-models.artifacts);
assert !(builtins.elem "qwen38-flash-next-abliterated-rocmfp4-gguf" self.nixosConfigurations.strix-worker.config.services.local-models.artifacts);
assert models."qwen3.8-27b-ara".capabilities.context == 102400;
assert models."qwen3.8-flash-next-abliterated".capabilities.context == 32768;
assert builtins.all (id: builtins.elem id c.services.local-models.artifacts) [
  "qwen38-27b-heretic-ara-q8-gguf"
  "qwen38-flash-next-abliterated-rocmfp4-gguf"
];
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
