{
  pkgs,
  self,
  inputs,
}:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  worker = self.nixosConfigurations.strix-worker.config;
  emb = models."qwen3-embedding-8b";
  embCfg = c.services.gufo-embedding;
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
    "qwen3-embedding-8b"
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
# The one embedding route (Tom, 2026-11-10): Gufo v0.33.0 with the vendored
# Qwen3-Embedding-8B extension compiled in, loaded on demand behind the same
# endpoint and swapped like every other route (no groups, asserted below), so
# it is never resident beside Flash-Next.
assert embCfg.enable;
assert builtins.elem "qwen3-embedding-8b-q8-gguf" c.services.local-models.artifacts;
assert emb.checkEndpoint == "/ready" && emb.ttl == 600;
assert emb.useModelName == "qwen3-embedding-8b";
assert !(emb ? capabilities);
assert pkgs.lib.hasSuffix "-gufo-demand-embedding-qwen3-embedding-8b \${PORT}" emb.cmd;
assert pkgs.lib.hasPrefix "${embCfg.package}/bin/gufo serve " embCfg.command;
assert pkgs.lib.hasInfix
  " serve --host 127.0.0.1 --port $GUFO_DEMAND_PORT embedding --model /var/lib/local-models/qwen3-embedding-8b-q8-gguf/Qwen3-Embedding-8B-Q8_0.gguf --served-model-name qwen3-embedding-8b"
  embCfg.command;
assert !(pkgs.lib.hasInfix " -hf" embCfg.command);
# The extension's provider is compiled in: only that form carries the
# metadata mkGufoServe validates the embedding modality against.
assert builtins.elem "qwen3-embedding" (map (p: p.id) embCfg.package.extensionMetadata.providers);
# Engine isolation: the fleet engine is untouched and the embedding engine is
# reached only through its launcher.
assert c.services.gufo.package == inputs.gufo.packages.x86_64-linux.default;
assert embCfg.package != c.services.gufo.package;
assert !(builtins.elem embCfg.package c.environment.systemPackages);
# The worker has no embedding route and no loan.
assert !worker.services.gufo-embedding.enable;
assert !(worker.services.llama-swap.settings.models ? "qwen3-embedding-8b");
assert !(builtins.elem "qwen3-embedding-8b-q8-gguf" worker.services.local-models.artifacts);
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
